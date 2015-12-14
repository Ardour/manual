#!/usr/bin/env ruby

require 'pathname'
require 'yaml'
require 'optparse'

require 'fileutils'

begin require 'liquid'
rescue LoadError
    puts "Please install the 'liquid' Ruby gem (available in Debian/Ubuntu as 'ruby-liquid')"
    exit 1
end

CONFIG = {
    pages_dir: '_manual',
    layouts_dir: '_layouts',
    static_dir: 'source',
    output_dir: '_site'
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
        unless system("rsync -a --delete --exclude='*~' #{static_dir}/. #{output_dir}")
            puts "Couldn't copy static files, is rsync installed?"
        end
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

	relative_path = @path.relative_path_from(@site.pages_dir);
	a = relative_path.each_filename.map do |x|
            x.sub(/^[0-9]*[-_]/, '')
        end
	a[-1].sub!(/\.html$/, '')
        s = a.join('/')

        @out_path = @site.output_dir + Pathname(s) + Pathname("index.html")
        @url = "/#{s}/"
        @sort_url = @path.to_s.sub(/\.html$/, '')
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

class Tag_children_hardcopy < Liquid::Tag
    def render(context)
        children = context.registers[:page].children
        entries = children.map {|p| "<li><a href='#{p.url}'>#{p.title}</a></li>" }

        ""

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
        begin require 'listen'
        rescue LoadError
            puts "To use the --watch function, please install the 'listen' Ruby gem"
            puts "(available in Debian/Ubuntu as 'ruby-listen')"
            return nil
        end

        listener = Listen.to(CONFIG[:pages_dir], wait_for_delay: 1.0, only: /.html$/) do |modified, added, removed|
            Site.new.build
        end
        listener.start
        listener
    end

    def run(options)
        require 'webrick'
	listener = options[:watch] && start_watcher
        port = options[:port] || 8000

        puts "Serving at http://localhost:#{port}/ ..."
        server = WEBrick::HTTPServer.new :Port => port, :DocumentRoot => CONFIG[:output_dir]
	trap 'INT' do
            server.shutdown
        end
     	server.start
        listener.stop if listener
    end
end

def main
    Liquid::Template.register_tag('tree', Tag_tree)
    Liquid::Template.register_tag('prevnext', Tag_prevnext)

    if defined? Liquid::Template.error_mode
        Liquid::Template.error_mode = :strict
    end

    options = {}
    OptionParser.new do |opts|
	opts.banner = %{Usage: build.rb <command> [options]

Use 'build.rb' to build the manual.  Use 'build.rb serve' to also
start a web server; setting any web server options implies "serve".
}
        opts.on("-w", "--watch", "Watch for changes") { options[:watch] = true }
        opts.on("-p", "--port N", Integer, "Specify port for web server") { |p| options[:port] = p }
        opts.on("-h", "--hardcopy", "Generate hardcopy") { options[:hardcopy] = true }
    end.parse!

    if options[:hardcopy]
        CONFIG[:layouts_dir] = '_layouts_hardcopy'
        CONFIG[:output_dir] = '_site_hardcopy'
        Liquid::Template.register_tag('children', Tag_children_hardcopy)
    else
        Liquid::Template.register_tag('children', Tag_children)
    end

    Site.new.build

    if options[:hardcopy]
      process_hardcopy
      generate_hardcopy
    end

    if options[:watch] || options[:port] || (ARGV.length > 0 && "serve".start_with?(ARGV[0]))
        Server.new.run(options)
    end
end

def is_external? (line)
    is_external = false

=begin

    http_pos = line.index('http:')
    if !http_pos.nil?
        if http_pos == 0
            is_external = true
        else
            is_external = false
        end
    end

    https_pos = line.index('https:')
    if !https_pos.nil?
        is_external = true if https_pos == 0
    end
=end

    is_external = true if line.include? 'http://'
    is_external = true if line.include? 'https://'

    return is_external
end

def has_extension? (line, delimiter)
    dot_pos = line.index('.')
    end_pos = line.index(delimiter)
    has_extension = false

    if !dot_pos.nil? && !end_pos.nil?
        has_extension = true if dot_pos < end_pos
    end

    return has_extension
end

def adjust_for_missing(remaining, delimiter)
    pos = remaining.index('missing' + delimiter)
    end_pos = remaining.index(delimiter)

    if !pos.nil?
        if pos == 0
            remaining = 'welcome-to-ardour' + remaining[end_pos, remaining.length - end_pos]
        end
    end

    return remaining
end

def get_hash(remaining, delimiter)
    end_pos = remaining.index(delimiter)
    hash_pos = remaining.index('#')
    the_hash = ""

    if !end_pos.nil? && !hash_pos.nil?
        the_hash = remaining[hash_pos, end_pos - hash_pos]
    end

    return the_hash
end

def strip_hash(remaining, save_hash)
    if !save_hash.empty?
        if remaining[0] == '#'
            # add base url in front of hash
            base = $hardcopy_path.sub(CONFIG[:output_dir], '').sub('index.html', '')
            base = base[1, base.length - 1]
            remaining = base + remaining
        end

        return remaining.sub(save_hash,'')
    else
        return remaining
    end
end

def adjust_hardcopy_hrefs (line, prefix, delimiter)
    new_line = ""
    remaining = line

    prefix << delimiter

    while !remaining.empty? do
        start_pos = remaining.index(prefix)
        if start_pos.nil?
            # done with the line
            new_line << remaining
            remaining = ''
        elsif start_pos == 0
            # do it to it
            new_line << prefix
            remaining = remaining[prefix.length, remaining.length - prefix.length]

            # now we're past opening delimiter
            # hopefully nobody is putting a delimiter into a file or directory name!
            return new_line if remaining.empty?

            if !is_external?(remaining)
                #we have a relative link so let's fixup
                new_line += 'file://' + Dir.pwd + '/_site_hardcopy/'
                if remaining[0] == '/'
                    remaining = remaining[1, remaining.length - 1] # some might be missing leading slash
                end

                # adjust for a '/missing' placeholder link
                remaining = adjust_for_missing(remaining, delimiter)
                save_hash = get_hash(remaining, delimiter)
                remaining = strip_hash(remaining, save_hash)

                # check for an extension like .png
                if !has_extension?(remaining, delimiter)
                    end_pos = remaining.index(delimiter)
                    # we need to add the index.html to end
                    if remaining[end_pos - 1] == '/'
                        new_line << remaining[0, end_pos] + 'index.html' + save_hash
                    else
                        new_line << remaining[0, end_pos] + '/index.html' + save_hash
                    end
                    remaining = remaining[end_pos, remaining.length - end_pos]
                end
            end

        else
            # advance to start of prefix
            new_line << remaining[0,start_pos]
            remaining = remaining[start_pos, remaining.length - start_pos]
        end
    end

    return new_line
end

def process_hardcopy
    Find.find(CONFIG[:output_dir]) do |path|
        if FileTest.directory?(path)
            next
        elsif path.include? 'index.html'
            $hardcopy_path = path
            temp_file = File.open(path + '.tmp', 'w')
            File.open(path, 'r') do |f|
                lines = f.readlines

                lines.each do |line|
                    adjust1 = adjust_hardcopy_hrefs(line, 'href=', "'");
                    adjust2 = adjust_hardcopy_hrefs(adjust1, 'href=', '"');
                    adjust3 = adjust_hardcopy_hrefs(adjust2, 'src=', "'");
                    adjust4 = adjust_hardcopy_hrefs(adjust3, 'src=', '"');
                    temp_file.puts(adjust4)
                end

                f.close
            end

            temp_file.close
            FileUtils.mv(path, path + ".original", :force=>true)
            FileUtils.mv(path + ".tmp", path, :force=>true)
        end
    end
end

def wk_args
    files = Array.new
    Find.find(CONFIG[:pages_dir]) do |path|
        files << path if path.end_with? '.html'
    end

    printf 'sorting...'
    files.sort!
    puts 'done'

    pwd = Dir.pwd
    output = CONFIG[:output_dir]
    puts '"' + pwd + '" "' + output + '"'

    wkhtml_args = File.open('wkhtmltopdf.args', 'w')

    files.each do |path|
        path = path.sub('.html', '/index.html')
        path = path.sub('_manual/', 'file://' + pwd + '/' + output + '/')
        path = path.gsub(/[0-9][0-9][_]/, '')

        wkhtml_args.puts path
    end

    wkhtml_args.puts 'source/files/ardour_manual.pdf'
    wkhtml_args.close
end

def generate_hardcopy
    FileUtils.rm 'wkhtmltopdf.args', :force=>true
    FileUtils.rm 'ardour_manual.pdf', :force=>true

    wk_args
    wkhtmltopdf = `xargs -a wkhtmltopdf.args wkhtmltopdf -q --load-error-handling ignore  \
        -n --enable-internal-links --image-quality 96 --orientation Landscape --dump-outline outline.txt \
        --footer-left "Created from http://manual.ardour.org/ on [isodate]" --footer-right "Page [page] of [toPage]" \
        --footer-line`

end

main
