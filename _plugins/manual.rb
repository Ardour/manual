require 'find'

module Manual
  
  def Manual.make_permalink (s)
    ('/' + s).gsub(/\/\d+[-_]/, '/').sub(/\.html$/, '/')
  end

  def Manual.child_url?(a, b)
    a.start_with?(b) && b.count('/') + 1 == a.count('/')
  end

  def Manual.find_children (url, site)
    site.pages.select{ |p| child_url?(p.url, url) }.sort_by{ |p| p.basename }
  end

  class ManualGenerator < Jekyll::Generator
    def generate(site)
      source = Pathname.new (site.config['source'])

      Dir.chdir (source) do

        manual_dir = Pathname.new('_manual/.')

        manual_dir.find do |path|
          if path.file? 
            plink = Manual.make_permalink(path.relative_path_from(manual_dir).to_s)
         
            page = Jekyll::Page.new(site, '', path.dirname.to_s, path.basename.to_s)
            page.data['permalink'] = plink

            site.pages << page
          end
        end
      end
    end
  end

  class Tag_tree < Liquid::Tag
    def join(children_html)
      children_html.empty? ? "" : "<dl>\n" + children_html.join + "</dl>\n"
    end

    def render(context)
      current_url = context['page.url']
      site = context.registers[:site]

      format_entry = lambda do |page|
        url = page.url
        title = page.data['title']
        css = ""
        children_html = ""
        
        children = Manual.find_children(url, site)
  
        if url == current_url
          css = ' class="active"'
        end
        if current_url.start_with?(url) || Manual.child_url?(current_url, url)
          children_html = join(children.map(&format_entry))
        end

        %{
          <dt#{css}>
            <a href='#{url}'>#{title}</a>
          </dt>
          <dd#{css}>
            #{children_html}
          </dd>
        }
      end

      join(Manual.find_children('/', site).map(&format_entry))
    end
  end

  class Tag_children < Liquid::Tag
    def render(context)
      page = context.registers[:page]       # for some reason this is not a Jekyll::Page object
      site = context.registers[:site]
      children = Manual.find_children(page['url'], site)
      entries = children.map do |child|
        url, title = child.url, child.data['title']
        "<li><a href='#{url}'>#{title}</a></li>"
      end

      "<div id='subtopics'>
        <h2>This chapter covers the following topics:</h2>
        <ul>
          #{entries.join}
        </ul>
        </div>
      "
    end
  end

end

Liquid::Template.register_tag('tree', Manual::Tag_tree) 
Liquid::Template.register_tag('children', Manual::Tag_children) 
