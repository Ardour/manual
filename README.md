
# The Ardour Manual


This is the project that generates the static ardour manual website available at [manual.ardour.org](http://manual.ardour.org).

The site is built using ruby (I use 1.9[.3]).

### Get the code

    git clone <repo-url> ardour-manual
    cd ardour-manual

## Structure of the content

There are 2 different types of content:

- special `_manual` content
- normal content

### Special `_manual` content

This is content that ends up as part of the tree on the left.

The _raw_ content is in `_manual/` directory and has a naming convention as follows:

    # content for a page at http://manual.ardour.org/<slug>/

    <ordering>_<slug>.<html|md|textile>
       ^          ^     ^
       |          |     |
       |          |   extension is removed later
       |          |
       |     ends up as part of URL
       |
     only used for ordering


    # a folder for subcontent is like this

    <ordering>_<slug>/

    # more things can then go in here for http://manual.ardour.org/<slug>/<slug2>/

    <ordering>_<slug>/<ordering2>_<slug2>.html

So, for example:


| this file                        | appears at url      |
|--------------------------------------------------------|
| _manual/01_main.html             | /main/              |
| _manual/01_main/01_subpage.html  | /main/subpage/      |


### Normal content

This is anything else, css files, images, fixed pages, layouts. This content lives in the `source` directory.

If you added `source/images/horse.png` is would be available at the url `/images/horse.png` after publishing it.

Content processing is applied to normal content if it has the correct header as described below.


## Content processing

Three types of content can have special processing done.

- `.html` liquid/HTML files
- `.md` markdown files
- `.textile` textile files

All files to be processed should also have a special header at the top too:

    ---
    layout: default
    title: Some Very Wordy and Expressive Title
    menu_title: Some Title
    ---

    <p>My Actual Content</p>

The `title` field will end up as an `h1` in the right panel. The `menu_title` is what is used in the menu tree on the left (if not preset it will default to using `title`).

### `.html` files

These are almost normal html, but extended with [Liquid templates](http://liquidmarkup.org/). There are a couple of special tags created for this project.

- `{% tree %}` is what shows the manual structure in the left column
- `{% children %}` shows the immediate list of children for a page


## More Advanced Stuff

You probably don't want or need to do any of this, but here are some
notes just in case you decide to anyway.

### Run it locally

You may want the manual available on a machine that doesn't have constant
internet access.

1. Download code and build manual

  ```
  git clone <repo-url> ardour-manual
  cd ardour-manual
  cp -r source _site
  ruby ./build.rb
  chmod -R a+rx _site
  ```

2. open `ardour-manual/_site/index.html` in your favorite web browser

  If this page doesn't open and function correctly, follow these optional steps to serve up the page with nginx.

3. Install [nginx](http://wiki.nginx.org/Install)
4. Configure nginx server block

  ```
  server {
      listen 80;
      server_name localhost;

      root /path_to_your_ardour-manual_folder;
      index index.html;
  }
  ```

5. Restart nginx server

        service nginx restart

6. The manual will now be available at http://localhost

### manual.rb plugin

Much of the functionality comes from `_plugins/manual.rb` - it takes the _manual format_ (contained in `_manual/`) and mushes it around a bit into a tmp directory.

This is to enable the directory tree to be understood, child page lists to be constructed, clean URLs, and the correct ordering of pages maintained.

### Clean URLs

To allow the clean URLs (no `.html` extension) _and_ to support simple hosting (no `.htaccess` or apache configuration required) each page ends up in it's own directory with an `index.html` page for the content.

E.g. `02_main/05_more/02_blah.html` after all processing is complete would end up in `_site/main/more/blah/index.html`.

The page format contained in the `_manual/` directory is different to the final rendered output (see special `_manual` content above) to make it simple to create content (you don't need to think about the `index.html` files).




