require 'erb'
require 'fileutils'
require 'tmpdir'
require 'pp'

module Manual

  DIRECTORY_ENTRIES = {}

  def self.traverse_data(entries, directory_sort = false, paths = [], key_paths = [], &block)

    entries.map do |entry|

      entry = entry.dup

      if entry[:type] == 'directory'
        entry[:children] = traverse_data(entry[:children], directory_sort, paths + [entry[:name]], key_paths + [entry[:key]], &block)
      end
      block_given? ? block.call(entry) : entry
    end
  end

  def self.traverse(path, directory_sort = false, paths = [], key_paths = [], &block)

      entries = Dir.glob(File.join(path,'*')).sort

      entries.sort_by! { |e| File.directory?(e) ? 1 : 0  } if directory_sort

      entries.map do |entry|
          is_dir = File.directory?(entry)

          data = extract_data(is_dir ? "#{entry}.html" : entry)

          short_title = data['menu_title'] || data['title']

          name = entry[/[^\/]+$/] # filename
          key = name.sub(/^[0-9]+(\-|_)/,'').sub(/\.[^\.]+$/,'') # slug
          my_paths = paths + [name]
          my_key_paths = key_paths + [key]
          url = '/' + my_key_paths.join('/') + '/'

          without_extension = entry.sub(/\.[^\/\/]+$/,'')

          h = {
              name: name,
              title: data['title'] || key,
              menu_title: short_title || key,
              key: key,
              filename: entry,
              type: is_dir ? 'directory' : 'file',
              url: url
          }

          if is_dir
              h.update \
                  children: traverse(entry, directory_sort, my_paths, my_key_paths, &block)
          else
              h.update extension: File.extname(name), has_dir: File.directory?(without_extension)
          end

          if is_dir
            DIRECTORY_ENTRIES[url] = h
          end

          block_given? ? block.call(h) : h
      end.compact
    end

    def self.extract_data(filename)
      if File.exists?(filename) and !File.directory?(filename) and first3 = File.open(filename) { |fd| fd.read(3) } and first3 == '---'
        blah = filename.sub(/^_manual\//,'')
        page = Jekyll::Page.new(@site, '_manual', File.dirname(blah), File.basename(blah))
        page.data
      else
        {}
      end
    end

  class ManualPage < Jekyll::Page
    def initialize(*args)
      super
    end
  end

  class ManualGenerator < Jekyll::Generator

    safe true
    
    def generate(site)
      source = site.config['source']
      destination = site.config['destination']

      manual_dir = '_manual'

      # now we need to turn our raw input files into something for jekyll to process
      # everything is in a directory with it's name and all content is in index.html files
      # the tmpdir gets removed at the end of this block automatically

      Dir.mktmpdir do |tmpdir|

        Manual.traverse manual_dir, true do |entry|
          output_filename = File.join(tmpdir, entry[:url], "index#{entry[:extension]}")

          FileUtils.mkdir_p File.dirname(output_filename)
          
          next unless entry[:type] == 'file'

          File.open(output_filename, 'w+') do |f| 
            f << File.read(entry[:filename])
          end

          relative_filename = File.join(entry[:url], "index#{entry[:extension]}")

          site.pages << Jekyll::Page.new(site, tmpdir, File.dirname(relative_filename), File.basename(relative_filename))
        end

      end
    end

  end

  class ManualChildPageTag < Liquid::Tag
    def render(context)
      current = context['page.url'].sub(/[^\/]+$/,'')

      if entry = DIRECTORY_ENTRIES[current]

        path = File.join(entry[:filename], '*')

        entries = entry[:children].map do |child|
          "<li><a href='#{child[:url]}'>#{child[:title]}</a></li>"
        end.uniq

        "<div class='chapter_content'>
        <p>This chapter covers:</p>
        <ul>
          #{entries.join}
        </ul>
        </div>
        "
      end
    end
  end

  # generates a big <dl> list of the manual page stucture

  class ManualTOCTag < Liquid::Tag

    def process_hierarchy(items_a, items_b)
      current = true
      position = nil
      level = -1

      [items_a.length,items_b.length].max.times do |i|
        a = items_a[i]
        b = items_b[i]

        current = false if a != b

        # start incrementing this when we don't have either a or b
        level += 1 if !a || !b

        if a && b
          return [false] if a != b
        elsif a
          position = :parent
        elsif b
          position = :child
        end
      end
      position ? [current, position, level + 1] : [current]
    end

    def render(context)

      @source = '_manual' #context.registers[:site].source

      @@data_tree ||= Manual.traverse(@source)

      @site = context.registers[:site]
      current = context['page.url'].sub(/[^\/]+$/,'')

      current_a = current.split('/').reject(&:empty?)

      tree = Manual.traverse_data(@@data_tree) do |entry|
      
          url = entry[:url]

          url_a = url.split('/').reject(&:empty?)

          depth = url_a.length
          is_current, position, level = *process_hierarchy(current_a, url_a)
          
          # this massively speeds up build time by not including the whole menu tree for each page
          next if depth > 1 && current_a[0] != url_a[0]

          css_classes = []
          css_classes << 'active' if is_current
          css_classes << position.to_s if position
          css_classes << "#{position}-#{level}" if position && level
          css_classes << 'other' unless is_current || position || level

          css_classes << "level-#{depth}"
          css_classes = css_classes.join(' ')

          if entry[:type] == 'directory'

              erb = ::ERB.new <<-HTML
                  <dt class="<%= css_classes %>">
                      <a href="<%= entry[:url] %>"><%= entry[:menu_title] %></a>
                  </dt>
                  <dd class="<%= css_classes %>">
                      <% if entry[:children].any? %>
                        <dl>
                            <%= entry[:children].join %> 
                        </dl>
                      <% end %>
                  </dd>
              HTML

              erb.result(binding)
          else

              directory_filename = entry[:filename].sub(/\.[^\/\.]+$/,'')

              unless entry[:has_dir]

                erb = ::ERB.new <<-HTML
                    <dt class="<%= css_classes %>">
                        <a href="<%= entry[:url] %>"><%= entry[:menu_title] %></a>
                    </dt>
                    <dd class="<%= css_classes %>">
                    </dd>
                HTML

                erb.result(binding)
             end
          end
          
         
      end

      "<dl>#{tree.join}</dl>
      <script type='text/javascript'>
      //<![CDATA[
        offset = document.getElementsByClassName('active')[0].offsetTop;
        height = document.getElementById('tree').clientHeight;
        if (offset > (height * .7)) {
          tree.scrollTop = offset - height * .3;
        }
      //]]>
      </script>"

    end


  end

end

Liquid::Template.register_tag('tree', Manual::ManualTOCTag) 
Liquid::Template.register_tag('children', Manual::ManualChildPageTag) 
