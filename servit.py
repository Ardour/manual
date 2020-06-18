#!/usr/bin/python3
#
# Script to locally host the manual as a simple http site

import os
import cherrypy

PATH = os.path.abspath(os.path.dirname(__file__))

class Root(object):
	pass

cherrypy.tree.mount(Root(), '/', config={
	'/': {
		'tools.staticdir.on': True,
		'tools.staticdir.dir': os.path.join(PATH, 'website'),
		'tools.staticdir.index': 'index.html',
	},
})

cherrypy.engine.start()
cherrypy.engine.block()
