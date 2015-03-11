require 'pathname'
require 'fileutils'
require 'yaml'
require 'liquid'
require 'optparse'

CONFIG = {
    pages_dir: '_manual',
    layouts_dir: '_layouts',
    static_dir: 'source',
    output_dir: '_site'         # will get wiped!
}

def child_url?(a, b)
    a.start_with?(b) && b.count('/') + 1 == a.count('/')
end

class Site
    attr_reader :pages, :layouts

    def initialize()
        @pages = []
        @layouts = {}
    end
    
    def build()
        print "Building... "

        read_layouts()
        read_pages()
        copy_static()
        process_pages()

        puts "done."
    end

    def read_layouts()
        Pathname.glob(layouts_dir + Pathname('*.html')) do |path|
            next if !path.file?
            layout = Layout.new(self, path)
            layout.read
            @layouts[path.basename('.html').to_s] = layout
        end
    end
    
    def read_pages()
        pages_dir.find do |path|
            if path.file? && path.extname == '.html'
                page = Page.new(self, path)
                page.read
                @pages << page
            end
        end
    end

    def process_pages()
        @pages.each {|page| page.process}
    end
    
    def copy_static()
        `rsync -a --delete --exclude='*~' #{static_dir}/. #{output_dir}`
    end
    
    def find_children(url)
        sorted_pages.select { |p| child_url?(p.url, url) }
    end
    
    def toplevel() @toplevel_memo ||= find_children('/') end
    def sorted_pages() @sorted_pages_memo ||= @pages.sort_by{ |p| p.sort_url } end

    def pages_dir() @pages_dir_memo ||= Pathname(CONFIG[:pages_dir]) end
    def layouts_dir() @layouts_dir_memo ||= Pathname(CONFIG[:layouts_dir]) end
    def static_dir() @static_dir_memo ||= Pathname(CONFIG[:static_dir]) end
    def output_dir() @output_dir_memo ||= Pathname(CONFIG[:output_dir]) end
end

class Page
    attr_reader :path, :out_path, :url, :sort_url

    def initialize(site, path)
        @site = site
        @path = path

        canon = canonical
        @out_path = @site.output_dir + canon + Pathname("index.html")
        @url = '/' + canon + '/'
        @sort_url = @path.to_s.sub(/\.html$/, '')
    end

    def canonical()
        remove_numbers = lambda {|x| x.sub(/^[0-9]*[-_]/, '') }
        path = @path.relative_path_from(@site.pages_dir)
        a = path.each_filename.map(&remove_numbers)
        a[-1] = a[-1].sub(/\.html$/, '')
        a.join('/')
    end

    def related_to?(p)
        # should we show p in the index on selfs page?
        url.start_with?(p.url) || child_url?(url, p.url)
    end

    def title()
        @page_context['title'] || ""
    end

    def menu_title()
        @page_context['menu_title'] || title
    end

    def read()
        content = @path.read
        frontmatter, @content = split_frontmatter(content) || abort("File not well-formatted: #{@path}") 
        @page_context = YAML.load(frontmatter)
        @template = Liquid::Template.parse(@content)
    end        

    def split_frontmatter(txt)
        @split_regex ||= /\A---[ \t\r]*\n(?<frontmatter>.*?)^---[ \t\r]*\n(?<content>.*)\z/m
        match = @split_regex.match txt 
        match ? [match['frontmatter'], match['content']] : nil
    end
    
    def find_layout()
        @site.layouts[@page_context['layout'] || 'default']
    end

    def children()
        @children ||= @site.find_children(@url)
    end
    
    def render()
        registers = {page: self, site: @site}
        context = {'page' => @page_context}
        content = @template.render!(context, registers: registers)
        find_layout.render(context.merge({'content' => content}), registers)
    end
    
    def process()
        path = out_path
        path.dirname.mkpath
        path.open('w') { |f| f.write(render) }
    end
end

class Layout < Page
    def render(context, registers)
        context = context.dup
        context['page'] = @page_context.merge(context['page'])
        content = @template.render!(context, registers: registers)
        if @page_context.has_key?('layout')
            find_layout.render(context.merge({'content' => content}), registers)
        else
            content
        end
    end
end

class Tag_tree < Liquid::Tag
    def join(children_html)
        children_html.empty? ? "" : "<dl>\n" + children_html.join + "</dl>\n"
    end

    def render(context)
        current = context.registers[:page]
        site = context.registers[:site]

        format_entry = lambda do |page|
            children = page.children
            
            css = (page == current) ? ' class="active"' : ""
            children_html = current.related_to?(page) ? join(children.map(&format_entry)) : ""
            
            %{
          <dt#{css}>
            <a href='#{page.url}'>#{page.menu_title}</a>
          </dt>
          <dd#{css}>
            #{children_html}
          </dd>
        }
        end

        join(site.toplevel.map(&format_entry))
    end
end

class Tag_children < Liquid::Tag
    def render(context)
        children = context.registers[:page].children
        entries = children.map {|p| "<li><a href='#{p.url}'>#{p.title}</a></li>" }
        
        "<div id='subtopics'>
        <h2>This chapter covers the following topics:</h2>
        <ul>
          #{entries.join}
        </ul>
        </div>
      "
    end
end

class Tag_prevnext < Liquid::Tag
    def render(context)
        current = context.registers[:page]
        pages = context.registers[:site].sorted_pages
        
        index = pages.index { |page| page == current }
        return '' if !index
        
        link = lambda do |p, cls, txt| 
            "<li><a title='#{p.title}' href='#{p.url}' class='#{cls}'>#{txt}</a></li>"
        end
        prev_link = index > 0 ? link.call(pages[index-1], "previous", " &lt; Previous ") : ""
        next_link = index < pages.length-1 ? link.call(pages[index+1], "next", " Next &gt; ") : ""
        
        "<ul class='pager'>#{prev_link}#{next_link}</ul>"
    end
end

class Server
    def start_watcher()
	require 'listen'

        listener = Listen.to(CONFIG[:pages_dir], wait_for_delay: 1.0, only: /.html$/) do |modified, added, removed|
            Site.new.build
        end
        listener.start
        listener
    end

    def run(options)
        require 'webrick'
	listener = options[:watch] && start_watcher
	    
        puts "Serving at http://localhost:8000/ ..."
        server = WEBrick::HTTPServer.new :Port => 8000, :DocumentRoot => CONFIG[:output_dir]
	trap 'INT' do 
            server.shutdown 
        end
     	server.start
        listener.stop if listener
    end  
end

def main
    Liquid::Template.register_tag('tree', Tag_tree)
    Liquid::Template.register_tag('children', Tag_children)
    Liquid::Template.register_tag('prevnext', Tag_prevnext)

    if defined? Liquid::Template.error_mode
        Liquid::Template.error_mode = :strict
    end

    options = {}
    OptionParser.new do |opts| 
        opts.on("--watch", "Watch for changes") { options[:watch] = true }
    end.parse!

    Site.new.build

    if ARGV == ['serve']
        Server.new.run(options)
    end
end

main
