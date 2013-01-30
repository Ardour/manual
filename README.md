
The Ardour Manual
===================

This is the project that generates the static ardour manual website available at http://manual.ardour.org.

The site is built using ruby (I use 1.9.3) and [Jekyll]](https://github.com/mojombo/jekyll) (a ruby gem). You should be able to just install ruby and then `gem install jekyll`. There are no other dependencies.

To generate the site and run it up locally you can do something like:

    git clone <repo-url>
    cd ardour-manual
    ruby export.rb
    jekyll --server

To upload it (assuming your ssh key has been put on the server) you run:

   ./upload.sh


Strucuture of the content
----------------------

There are 2 different types of content:
- special manual content
- normal content

Special manual content
----------------------

This is content that ends up as part of the tree on the left.

The _raw_ content is in `_manual` directory and has a naming convention as follows:

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

    this file                  appears at
    ------------               ------------

    01_main.html               /main/

    01_main/01_subpage.html    /main/subpage/


Normal content
----------------------

This is anything else, css files, images, fixed pages, layouts. This content lives in the `source` directory.


Content processing
----------------------

Three types of content can have special processing done.

- `.html` files
- `.md` files
- `.textile` files

All special files should also have a special header at the top too:

    ---
    layout: default
    title: Some Very Wordy and Expressive Title
    menu_title: Some Title
    ---

    <p>My Actual Content</p>


    