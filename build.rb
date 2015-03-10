require 'pathname'
require 'fileutils'
require 'yaml'
require 'liquid'

def split_frontmatter(txt)
    re = /\A---[ \t\r]*\n(?<frontmatter>.*?)^---[ \t\r]*\n(?<content>.*)\z/m
    match = re.match txt 
    match ? [match['frontmatter'], match['content']] : nil
end

def child_url?(a, b)
    a.start_with?(b) && b.count('/') + 1 == a.count('/')
end

class Site
    attr_reader :pages

    def initialize()
        @pages = []
        @config = {
            'pages_dir' => '_manual',
            'layouts_dir' => '_layouts',
            'static_dir' => 'source',
            'output_dir' => '_site'
        }
        @layouts = {}
    end
    
    def read_layouts()
        layouts_dir = Pathname(@config['layouts_dir'])
        Pathname.glob(layouts_dir + Pathname('*.html')) do |path|
            next if !path.file?
            layout = Layout.new(self, path)
            layout.read
            @layouts[path.basename('.html').to_s] = layout
        end
    end
    
    def find_layout(name)
        @layouts[name]
    end
    
    def read_pages()
        pages_dir = Pathname.new(@config['pages_dir'])
        pages_dir.find do |path|
            if path.file? && path.extname == '.html'
                page = Page.new(self, path)
                page.read
                @pages << page
            end
        end
    end

    def find_children(url)
        @pages.select{ |p| child_url?(p.url, url) }.sort_by{ |p| p.path.basename }
    end
    
    def process_pages()
        @pages.each {|page| page.process}
    end
    
    def copy_static()
        # http://ruby-doc.org/stdlib-2.2.1/libdoc/fileutils/rdoc/index.html
    end
    
    def pages_dir()
        Pathname(@config['pages_dir'])
    end
    
    def output_dir()
        Pathname(@config['output_dir'])
    end

    def run()
        #read_config()
        read_layouts()
        read_pages()
        copy_static()
        process_pages()
    end
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
        if !@page_context
            puts 'nil page context: ' + @path.to_s
        end
        @page_context['title'] || ""
    end

    def read()
        content = @path.read
        split = split_frontmatter content
        split || abort("Not a Jekyll-formatted file: #{@path}") 
        frontmatter, @content = split
        @page_context = YAML.load(frontmatter)
        @template = Liquid::Template.parse(@content)
    end        
    
    def find_layout()
        @site.find_layout(@page_context['layout'] || 'default')
    end

    def children()
        @site.find_children(@url)
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
        path.write(render)
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
            <a href='#{page.url}'>#{page.title}</a>
          </dt>
          <dd#{css}>
            #{children_html}
          </dd>
        }
        end

        join(site.find_children('/').map(&format_entry))
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
        site = context.registers[:site]
        current = context.registers[:page]
        
        pages = site.pages.sort_by{ |p| p.sort_url }
        
        ind = pages.index { |page| page == current }
        return '' if !ind
        
        lnk = lambda do |p, cls, txt| 
            "<li><a title='#{p.title}' href='#{p.url}' class='#{cls}'>#{txt}</a></li>"
        end
        prev_link = ind > 0 ? lnk.call(pages[ind-1], "previous", " &lt; Previous ") : ""
        next_link = ind < pages.length-1 ? lnk.call(pages[ind+1], "next", " Next &gt; ") : ""
        
        "<ul class='pager'>#{prev_link}#{next_link}</ul>"
    end
end

Liquid::Template.register_tag('tree', Tag_tree)
Liquid::Template.register_tag('children', Tag_children)
Liquid::Template.register_tag('prevnext', Tag_prevnext)

Liquid::Template.error_mode = :strict

Site.new.run
