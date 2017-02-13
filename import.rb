require 'nokogiri'
require 'fileutils'
require 'open-uri'

URL = 'http://ardour.org/book/export/html/5848'
FILENAME = 'drupal-export.html'

WRITE = true
DOWNLOAD_FILES = false
GET_ARDOUR_ORG_IMAGES = false
HANDLE_OTHER_IMAGES = false

OUTPUT_DIR = '_manual'

FILES_DIR = 'source'

SLUG_MAPPINGS = {
    'working_with_sessions' => 'sessions',
    'export_stem' => 'export',
    'track_groups' => 'track_bus_groups',
    'vst_support' => 'windows_vst',
    'kbd_default' => 'default_bindings',
    'midistep_entry' => 'midi_step_entry',
    'midi_stepentry' => 'midi_step_entry'
}

MISSING_SLUGS = %w(
    range_selection
    track_templates
    track_template
    color_dialog
    region_layering
    round_robin_inputs
    mcp_osx
    mcp_new_device
)

FILES_MAPPINGS = {
    '/files/a3_mnemonic_cheatsheet.pdf' => '/files/ardour-2.8.3-bindings-x.pdf',
    '/files/a3_mnemonic_cheat_sheet_osx.pdf' => '/files/ardour-2.8.3-bindings-osx-a4.pdf'
}

LINK_SLUG_TO_NODE_ID = {}

def link_slug_to_node_id(slug)

    slug = SLUG_MAPPINGS[slug] || slug

    return nil if MISSING_SLUGS.include? slug

    LINK_SLUG_TO_NODE_ID[slug] ||= begin
        filename = "tmp/slug-to-node/#{slug}"

        if File.exists? filename
            File.read(filename).to_i
        else
            url = "http://ardour.org/manual/#{slug}"
            puts "opening #{url}"
            node_id = Nokogiri(open(url)).at('#content .node')['id'].sub(/^node\-/,'').to_i
            File.open(filename,'w+') { |f| f << node_id }
            node_id
        end
    end
end


def register_node(node_id, path)
    filename = "tmp/node-to-path/#{node_id}"
    File.open(filename,'w+') { |f| f << path } unless File.exists? filename
end

def node_id_to_path!(node_id)
    filename = "tmp/node-to-path/#{node_id}"
    return '' unless File.exists? filename
    #raise "no path for node-id #{node_id}" unless File.exists? filename
    File.read(filename)
end

def process(html, level = 1, path = [], numbered_path = [])
    html.search("div.section-#{level}").each_with_index do |child, i|

        title = child.at('h1.book-heading').inner_text

        node_id = child['id'].sub(/^node\-/,'')


        slug = title.downcase.gsub(' ','-').gsub(/[^a-z0-9\-]/, '')

        root = slug == 'the-ardour3-manual'

        if root

            # top level

            this_path = []
            this_numbered_path = []
        else
            numbered_slug = "%02d_%s" % [i + 1, slug, node_id]

            this_path = path + [slug]
            this_numbered_path = numbered_path + [numbered_slug]
        end

        register_node node_id, this_path.join('/')

        indent = ' ' * level * 3

        has_children = child.search("div.section-#{level + 1}").length > 0 #&& possible_children.any? { |child| child.search('div').length > 0 }

        output_dir = "#{OUTPUT_DIR}/#{this_numbered_path.join('/')}"

        output_file = case 
        when root
            "#{OUTPUT_DIR}/blah.html"
        #when has_children
        #    "#{output_dir}/index.html"
        else
            "#{output_dir}.html"
        end

        content = child.dup

        content.search('h1.book-heading').remove
        content.search("div.section-#{level + 1}").remove

        if heading = content.at('h2') and heading.inner_text == title
            heading.remove
        end

        #puts "processing links in [#{this_path.join('/')}]"

        content.search('a').each do |a|
            href = a['href']
            case href
            when /^\/manual\/(.*)/
                slug = $1
                if node_id = link_slug_to_node_id(slug)
                    link_path = node_id_to_path! node_id
                    #puts " link slug [#{slug}] -> #{node_id} -> #{link_path}"
                    a['href'] = "/#{link_path}"
                else
                    a['href'] = "/missing"
                end

            when /^(\/files\/.*)/

                if DOWNLOAD_FILES
                    file_path = $1


                    if FILES_MAPPINGS[file_path]
                        file_path = FILES_MAPPINGS[file_path]
                        a['href'] = file_path
                    end

                    puts "downloading [#{file_path}] (for #{this_path.join('/')})"

                    filename = "#{FILES_DIR}/#{file_path}"
                    FileUtils.mkdir_p File.dirname(filename)
                    File.open(filename,'w+') { |f| f << open("http://ardour.org/#{file_path}").read }
                end
            end
        end

        content.search('img').each do |img|

            src = img['src']

            case src
            when /^\//
                if GET_ARDOUR_ORG_IMAGES
                    url = "http://ardour.org#{src}"
                    puts "getting #{url}"
                    img_path = "#{FILES_DIR}#{src}"
                    FileUtils.mkdir_p File.dirname(img_path)
                    File.open(img_path, 'w+') { |f| f << open(url).read }
                end
            when /^http/
                new_src = '/' + src.sub(/^http:\/\/[^\/]+\//,'')
                img['src'] = new_src
                    
                if HANDLE_OTHER_IMAGES
                    puts "new_src: #{new_src}"
                    img_path = "#{FILES_DIR}#{new_src}"
                    FileUtils.mkdir_p File.dirname(img_path)
                    puts "getting #{src}"
                    File.open(img_path, 'w+') { |f| f << open(src).read }
                end
            end

        end

        if WRITE
            FileUtils.mkdir_p output_dir if has_children
            File.open(output_file, 'w:UTF-8') do |f| 
                f << <<-HTML
---
layout: default
title: #{title}
---                        

#{content.inner_html}
                HTML

                if has_children
                    f << <<-HTML
{% children %}
                    HTML
                end


            end
        end

        process(child, level + 1, this_path, this_numbered_path)
    end
end


unless File.exists?(FILENAME)
    puts "downloading #{URL} to #{FILENAME}"
    File.open(FILENAME,'w+') { |f| f << open(URL).read }
end

FileUtils.mkdir_p('tmp/node-to-path')
FileUtils.mkdir_p('tmp/slug-to-node')

process Nokogiri(File.read(FILENAME))

