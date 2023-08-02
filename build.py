#!/usr/bin/python3
#
# Script to take the master document and ancillary files and create the
# finished manual/website.
#
# by James Hammons
# (C) 2020 Underground Software
#
# Contributors: Ed Ward
#

# Remnants (could go into the master document as the first header)

import os
import re
import shutil
import argparse
import datetime

# Global vars
global_bootstrap_path = '/bootstrap-3.3.7'
global_page_title = 'The Ardour Manual'
global_site_dir = './website/'
global_manual_url = 'http://manual.ardour.org'
global_githuburl = 'https://github.com/Ardour/manual/edit/master/include/'
global_screen_template = 'page-template.html'
global_onepage_template = 'onepage-template.html'
global_pdf_template = 'pdf-template.html'
global_master_doc = 'master-doc.txt'
global_pdflink = '<button class="btn btn-default" type="button" onclick="window.location.href=\'/manual.pdf\'"><span class="glyphicon glyphicon-book" aria-hidden="true"></span></button>'
from datetime import datetime
global_today = datetime.today().strftime('%Y-%m-%d')
global_redirects_file = 'uri_to_fix.txt'

# This matches all *non* letter/number, ' ', '.', '-', and '_' chars
cleanString = re.compile(r'[^a-zA-Z0-9 \._-]+')
# This matches new 'unbreakable' links, up to the closing quote or anchor
findLinks = re.compile(r'"@@[^#"]*[#"]')

#
# Create an all lowercase filename without special characters and with spaces
# replaced with dashes.
#
def MakeFilename(s):
	global cleanString
	# Clean up the file name, removing all non letter/number or " .-_" chars.
	# Also, convert to lower case and replace all spaces with dashes.
	fn = cleanString.sub('', s).lower().replace(' ', '-')
	# Double dashes can creep in from the above replacement, so we check for
	# that here.
	fn = fn.replace('--', '-')

	return fn


#
# Parse headers into a dictionary
#
def ParseHeader(fileObj):
	header = {}

	while (True):
		hdrLine = fileObj.readline().rstrip('\r\n')

		# Break out of the loop if we hit the end of header marker
		if hdrLine.startswith('---'):
			break

		# Check to see that we have a well-formed header construct
		match = re.findall(': ', hdrLine)

		if match:
			# Parse out foo: bar pairs & put into header dictionary
			a = re.split(': ', hdrLine, 1)
			header[a[0]] = a[1]

	return header


#
# Turn a "part" name into an int
#
def PartToLevel(s):
	lvl = {'part': 0, 'chapter': 1, 'subchapter': 2, 'section': 3, 'subsection': 4 }

	if s in lvl:
		return lvl[s]

	return -1


#
# Converts a integer to a Roman numeral
#
def num2roman(num):
	num_map = [(1000, 'M'), (900, 'CM'), (500, 'D'), (400, 'CD'), (100, 'C'), (90, 'XC'), (50, 'L'), (40, 'XL'), (10, 'X'), (9, 'IX'), (5, 'V'), (4, 'IV'), (1, 'I')]
	roman = ''

	while num > 0:
		for i, r in num_map:
			while num >= i:
				roman += r
				num -= i

	return roman

#
# Capture the master document's structure (and content, if any) in a list
#
def GetFileStructure():
	fs = []
	fnames = [None] * 6
	content = ''
	grab = False
	mf = open(global_master_doc)

	for ln in mf:
		if ln.startswith('---'):
			# First, stuff any content that we may have read into the current
			# header's dictionary
			if grab:
				fs[-1]['content'] = content
				grab = False
				content = ''

			# Then, get the new header and do things to it
			hdr = ParseHeader(mf)
			level = PartToLevel(hdr['part'])
			hdr['level'] = level
			fnames[level] = MakeFilename(hdr['title'])

			# Ickyness--user specified URIs
			if 'uri' in hdr:
				hdr['filename'] = hdr['uri']
			else:
				fullName = ''

				for i in range(level + 1):
					fullName = fullName + fnames[i] + '/'

				# Strip trailing '/' on filename
				hdr['filename'] = fullName[:-1]

			fs.append(hdr)

			if ('include' not in hdr) and (level > 0):
				grab = True
		else:
			if grab:
				content = content + ln

	# Catch the last file, since it would be missed above
	if grab:
		fs[-1]['content'] = content

	mf.close()
	return fs


#
# Determine if a particular node has child nodes
#
def HaveChildren(fs, pos):
	# If we're at the end of the list, there can be no children
	if pos == len(fs) - 1:
		return False

	# If the next node is at a lower level than the current node, we have
	# children.
	if fs[pos]['level'] < fs[pos + 1]['level']:
		return True

	# Otherwise, no children at this node.
	return False


#
# Get the children at this level, and return them in a list
#
def GetChildren(fs, pos):
	children = []
	pos = pos + 1
	childLevel =  fs[pos]['level']

	while fs[pos]['level'] >= childLevel:
		if fs[pos]['level'] == childLevel:
			children.append(pos)

		pos = pos + 1

		# Sanity check
		if pos == len(fs):
			break

	return children


#
# Get the parent at this level
#
def GetParent(fs, pos):
	thisLevel =  fs[pos]['level']
	pos = pos - 1

	while pos >= 0 and fs[pos]['level'] >= thisLevel:
		pos = pos - 1

	return pos


#
# Change the hierarchy of titles : <h1>-><hn>, <h2>-><hn+1>, so that the
# highest hierarchy level is maxlevel
#
def remapheader(txt, maxlevel):
	maxlvl=1
	# find the highest hierarchy level in the content
	while maxlvl < 7 and txt.find('<h' + str(maxlvl)) == -1:
		maxlvl += 1
	# if there is a hierarchy, remap it so that the highest level is maxlevel
	if maxlvl < 7:
		for i in range(6, maxlvl-1, -1):
			txt = txt.replace('<h' + str(i), '<h' + str(i + maxlevel - maxlvl))
			txt = txt.replace('</h' + str(i), '</h' + str(i + maxlevel - maxlvl))

	return txt
	
#
# Creates the BreadCrumbs
#
def GetBreadCrumbs(fs, pos):
	breadcrumbs = '<li class="active">'+ fs[pos]['title'] + '</li>'

	while pos >= 0:
		pos = GetParent(fs, pos)

		if pos >= 0:
			breadcrumbs='<li><a href="/' + fs[pos]['filename'] + '/">'+ fs[pos]['title'] + '</a></li>'+ breadcrumbs

	breadcrumbs = '<ul class="breadcrumb"><li><a href="/toc/index.html">Home</a></li>' + breadcrumbs + '</ul>'
	return breadcrumbs


#
# Make an array of children attached to each node in the file structure
# (It's a quasi-tree structure, and can be traversed as such.)
#
def FindChildren(fs):
	childArray = []

	for i in range(len(fs)):
		if HaveChildren(fs, i):
			childArray.append(GetChildren(fs, i))
		else:
			childArray.append([])

	return childArray


#
# Make an array of the top level nodes in the file structure
#
def FindTopLevelNodes(fs):
	level0 = []

	for i in range(len(fs)):
		if fs[i]['level'] == 0:
			level0.append(i)

	return level0


#
# Find all header links and create a dictionary out of them
#
def FindInternalLinks(fs):
	linkDict = {}

	for hdr in fs:
		if 'link' in hdr:
			linkDict['"@@' + hdr['link'] + '"'] = '"/' + hdr['filename'] + '/"'
			linkDict['"@@' + hdr['link'] + '#'] = '"/' + hdr['filename'] + '/index.html#'

	return linkDict


#
# Same as above, but create anchors (for the one-page version)
#
def FindInternalAnchors(fs):
	linkDict = {}

	for hdr in fs:
		if 'link' in hdr:
			linkDict['"@@' + hdr['link'] + '"'] = '"#' + hdr['link'] + '"'
			linkDict['"@@' + hdr['link'] + '#'] = '"#' + hdr['link'] + '"'

	return linkDict


#
# Internal links are of the form '@@link-name', which are references to the
# 'link:' field in the part header. We have to find all occurrences and replace
# them with the appropriate link.
#
def FixInternalLinks(links, content, title):
	global findLinks
	match = findLinks.findall(content)
	missing = []

	if len(match) > 0:
		for s in match:
			if s in links:
				content = content.replace(s, links[s])
			else:
				missing.append(s)

	# Report missing link targets to the user (if any)
	if len(missing) > 0:
		print('\nMissing link target' + ('s' if len(missing) > 1 else '') + ' in "' + title + '":')

		for s in missing:
			print('  ' + s)

		print()

	return content


#
# Recursively build a list of links based on the location of the page we're
# looking at currently
#
def BuildList(lst, fs, pagePos, cList):
	content = '<ul>\n'

	for i in range(len(lst)):
		curPos = lst[i]
		nextPos = lst[i + 1] if i + 1 < len(lst) else len(fs)

		active = ' class=active' if curPos == pagePos else ''
		menuTitle = fs[curPos]['menu_title'] if 'menu_title' in fs[curPos] else fs[curPos]['title']
		content = content + '\t<li' + active + '><a href="/' + fs[curPos]['filename'] + '/">' + menuTitle + '</a></li>\n'

		# If the current page is our page, and it has children, enumerate them
		if curPos == pagePos:
			if len(cList[curPos]) > 0:
				content = content + BuildList(cList[curPos], fs, -1, cList)

		# Otherwise, if our page lies between the current one and the next,
		# build a list of links from those nodes one level down.
		elif (pagePos > curPos) and (pagePos < nextPos):
			content = content + BuildList(cList[curPos], fs, pagePos, cList)

	content = content + '</ul>\n'

	return content


#
# Builds the sidebar for the one-page version
#
def BuildOnePageSidebar(fs):

	content = '\n\n<ul class="toc">\n'
	lvl = 0
	levelNums = [0] * 5

	for i in range(len(fs)):
		# Handle Part/Chapter/subchapter/section/subsection numbering
		level = fs[i]['level']

		if level < 2:
			levelNums[2] = 0

		levelNums[level] = levelNums[level] + 1;
		j = level
		txtlevel = ''

		while j > 0:  #level 0 is the part number which is not shown
			txtlevel = str(levelNums[j]) + '.' + txtlevel
			j = j - 1

		if len(txtlevel) > 0:
			txtlevel = txtlevel[:-1] + ' - '

		if 'link' in fs[i]:
			anchor = fs[i]['link']
		else:
			anchor = fs[i]['filename']

		while lvl < level:
			content = content + '<ul class="toc">\n'
			lvl = lvl + 1

		while lvl > level:
			content = content + '</ul>\n'
			lvl = lvl - 1

		content = content + '<li><a href="#' + anchor + '">' + txtlevel + fs[i]['title'] + '</a></li>\n'

	content = content + '</ul>\n'

	return content


#
# Create link sidebar given a position in the list.
#
def CreateLinkSidebar(fs, pos, childList):

	# Build the list recursively from the top level nodes
	content = BuildList(FindTopLevelNodes(fs), fs, pos, childList)
	# Shove the TOC link and one file link at the top...
	active = ' class=active' if pos < 0 else ''
	content = content.replace('<ul>', '<ul><li' + active + '><a href="/toc/">Table of Contents</a></li>\n', 1)

	return content


# Preliminaries

# We have command line arguments now, so deal with them
parser = argparse.ArgumentParser(description='A build script for the Ardour Manual')
parser.add_argument('-v', '--verbose', action='store_true', help='Display the high-level structure of the manual')
parser.add_argument('-q', '--quiet', action='store_true', help='Suppress all output (overrides -v)')
parser.add_argument('-d', '--devmode', action='store_true', help='Add content to pages to help developers debug them')
parser.add_argument('-p', '--pdf', action='store_true', help='Automatically generate PDF from content')
args = parser.parse_args()
verbose = args.verbose
noisy = not args.quiet
devmode = args.devmode
pdf = args.pdf

# --quiet overrides --verbose, so tell it to shut up if user did both
if not noisy:
	verbose = False

level = 0
fileCount = 0
levelNums = [0] * 5
lastFile = ''
page = ''
onepage = ''
pdfpage = ''
toc = ''
pageNumber = 0

if noisy and devmode:
	print('Devmode active: scribbling extra junk to the manual...')

if os.access(global_site_dir, os.F_OK):
	if noisy:
		print('Removing stale HTML data...')

	shutil.rmtree(global_site_dir)

shutil.copytree('./source', global_site_dir)

# Read the template, and fix the stuff that's fixed for all pages
temp = open(global_screen_template)
template = temp.read()
temp.close()
template = template.replace('{{page.bootstrap_path}}', global_bootstrap_path)
template = template.replace('{{page.page_title}}', global_page_title)
if pdf:
	template = template.replace('{{page.page_pdflink}}', global_pdflink)
else:
	template = template.replace('{{page.page_pdflink}}', '')


# Same as above, but for the "One-Page" version
temp = open(global_onepage_template)
onepage = temp.read()
temp.close()
onepage = onepage.replace('{{page.bootstrap_path}}', global_bootstrap_path)
onepage = onepage.replace('{{page.page_title}}', global_page_title)

if pdf:
	# Same as above, but for the PDF version
	temp = open(global_pdf_template)
	pdfpage = temp.read()
	temp.close()
	pdfpage = pdfpage.replace('{{page.page_title}}', global_page_title)

# Parse out the master document's structure into a dictionary list
fileStruct = GetFileStructure()

# Build a quasi-tree structure listing children at level + 1 for each node
nodeChildren = FindChildren(fileStruct)

# Create a dictionary for translation of internal links to real links
links = FindInternalLinks(fileStruct)
oplinks = FindInternalAnchors(fileStruct)

if noisy:
	print('Found ' + str(len(links)) + ' internal link target', end='')
	print('.') if len(links) == 1 else print('s.')

if noisy:
	master = open(global_master_doc)
	firstLine = master.readline().rstrip('\r\n')
	master.close()

	if firstLine == '<!-- exploded -->':
		print('Parsing exploded file...')
	elif firstLine == '<!-- imploded -->':
		print('Parsing imploded file...')
	else:
		print('Parsing unknown type...')

# Here we go!

for header in fileStruct:
	fileCount = fileCount + 1
	content = ''
	more = ''

	lastLevel = level
	level = header['level']

	# Handle Part/Chapter/subchapter/section/subsection numbering
	if level < 2:
		levelNums[2] = 0

	levelNums[level] = levelNums[level] + 1;

	# This is totally unnecessary, but nice; besides which, you can capture
	# the output to a file to look at later if you like :-)
	if verbose:
		for i in range(level):
			print('\t', end='')

		if (level == 0):
			print('\nPart ' + num2roman(levelNums[0]) + ': ', end='')
		elif (level == 1):
			print('\n\tChapter ' + str(levelNums[1]) + ': ', end='')

		print(header['title'])

	# Handle TOC scriblings...
	if level == 0:
		toc = toc + '<h2>Part ' + num2roman(levelNums[level]) + ': ' + header['title'] + '</h2>\n';
	elif level == 1:
		toc = toc + '\t<p class="chapter">Ch. ' + str(levelNums[level]) + ':&nbsp;&nbsp;<a href="/' + header['filename'] + '/">' + header['title'] + '</a></p>\n'
	elif level == 2:
		toc = toc + '\t\t<p class="subchapter"><a href="/' + header['filename'] + '/">' + header['title'] + '</a></p>\n'
	elif level == 3:
		toc = toc + '<p class="section"><a href="/' + header['filename'] + '/">' + header['title'] + '</a></p>\n'
	elif level == 4:
		toc = toc + '<p class="subsection"><a href="/' + header['filename'] + '/">' + header['title'] + '</a></p>\n'

	# Make the 'this thing contains...' stuff
	if HaveChildren(fileStruct, pageNumber):
		pages = GetChildren(fileStruct, pageNumber)

		for pg in pages:
			more = more + '<li>' + '<a href="/' + fileStruct[pg]['filename'] + '/">' + fileStruct[pg]['title'] + '</a>' + '</li>\n'

		more = '<div id=subtopics>\n' + '<h2>This section contains the following topics:</h2>\n' + '<ul>\n' + more + '</ul>\n' + '</div>\n'

	parent = GetParent(fileStruct, pageNumber)

	# Make the 'Previous', 'Up' & 'Next' content
	nLink = ''
	pLink = ''
	uLink = ''

	if pageNumber > 0:
		pLink = '<li class="previous"><a title="' + fileStruct[pageNumber - 1]['title'] + '" href="/' + fileStruct[pageNumber - 1]['filename'] + '/" class="previous"> &larr; Previous </a></li>'

	if pageNumber < len(fileStruct) - 1:
		nLink = '<li class="next"><a title="' + fileStruct[pageNumber + 1]['title'] + '" href="/' + fileStruct[pageNumber + 1]['filename'] + '/" class="next"> Next &rarr; </a></li>'

	if level > 0:
		uLink = '<li><a title="' + fileStruct[parent]['title'] + '" href="/' + fileStruct[parent]['filename'] + '/" class="active"> &uarr; Up </a></li>'
	else:
		uLink = '<li><a title="Ardour Table of Contents" href="/toc/index.html" class="active"> &uarr; Up </a></li>'

	prevnext = '<ul class="pager">' + pLink + uLink + nLink + '</ul>'

	# Make the BreadCrumbs
	breadcrumbs = GetBreadCrumbs(fileStruct, pageNumber)

	# Create the link sidebar
	sidebar = CreateLinkSidebar(fileStruct, pageNumber, nodeChildren)

	# Parts DO NOT have any content, they are ONLY an organizing construct!
	# Chapters, subchapters, sections & subsections can all have content,
	# but the basic fundamental organizing unit WRT content is still the
	# chapter.
	githubedit = ''
	themechanger = '<span style="float:right;padding: 0 5px 5px 5px;position:relative;bottom:-5px;"><button class="theme-changer" onclick="changetheme()" title="Change Theme"></button></span>'

	if level > 0:
		if 'include' in header:
			srcFile = open('include/' + header['include'])
			githubedit = '<span style="float:right;padding:5px;"><a class="github-link" title="Edit in GitHub" href="' + global_githuburl + header['include'] + '"></a></span>'
			content = srcFile.read()
			srcFile.close()

			# Get rid of any extant header in the include file
			# (once this is accepted, we can nuke this bit, as content files
			# will not have any headers or footers in them)
			content = re.sub('---.*\n(.*\n)*---.*\n', '', content)
			content = content.replace('{% children %}', '')

		else:
			if 'content' in header:
				content = header['content']
			else:
				content = '[something went wrong]'

	# Add header information to the page if in dev mode
	if devmode:
		devnote ='<aside style="background-color:indigo; color:white;">'

		if 'filename' in header:
			devnote = devnote + 'filename: ' + header['filename'] + '<br>'

		if 'include' in header:
			devnote = devnote + 'include: ' + header['include'] + '<br>'

		if 'link' in header:
			devnote = devnote + 'link: ' + header['link'] + '<br>'

		content = devnote + '</aside>' + content

	# ----- One page and PDF version -----

	# Fix up any internal links
	opcontent = FixInternalLinks(oplinks, content, header['title'])
	opcontent = remapheader(opcontent, level+2)

	# Create "one page" header
	oph = '<h' + str(level+1) + ' class="clear" id="' + header[('link' if 'link' in header else 'filename')] +'">' + header['title'] + '</h' + str(level+1) + '>\n';

	# Set up the actual page from the template
	onepage = onepage.replace('{{ content }}', oph + '\n' + opcontent + '\n{{ content }}')

	if pdf:
		if not 'pdf-exclude' in header:
			pdfpage = pdfpage.replace('{{ content }}', oph + '\n' + opcontent + '\n{{ content }}')
		else:
			pdfpage = pdfpage.replace('{{ content }}', oph + '\n' + 'Please refer to the <a href="' + global_manual_url + '/' + header['filename'] + '/">online manual</a>.\n{{ content }}')

	# ----- Normal version -----

	# Fix up any internal links
	content = FixInternalLinks(links, content, header['title'])

	# Set up the actual page from the template
	if 'style' not in header:
		page = re.sub("{% if page.style %}.*\n.*\n{% endif %}.*\n", "", template)
	else:
		page = template.replace('{{page.style}}', header['style'])
		page = page.replace('{% if page.style %}', '')
		page = page.replace('{% endif %}', '')

	page = page.replace('{{ page.title }}', header['title'])
	page = page.replace('{% tree %}', sidebar)
	page = page.replace('{% prevnext %}', prevnext)
	page = page.replace('{% githubedit %}', githubedit)
	page = page.replace('{% themechanger %}', themechanger)
	page = page.replace('{% breadcrumbs %}', breadcrumbs)
	page = page.replace('{{ content }}', content + more)

	# Create the directory for the index.html file to go into (we use makedirs,
	# because we have to in order to accommodate the 'uri' keyword)
	os.makedirs(global_site_dir + header['filename'], 0o775, exist_ok=True)

	# Finally, write the file!
	destFile = open(global_site_dir + header['filename'] + '/index.html', 'w')
	destFile.write(page)
	destFile.close()

	# Save filename for next header...
	lastFile = header['filename']
	pageNumber = pageNumber + 1

# Finally, create the TOC
sidebar = CreateLinkSidebar(fileStruct, -1, nodeChildren)

page = re.sub("{% if page.style %}.*\n.*\n{% endif %}.*\n", "", template)
page = page.replace('{{ page.title }}', 'Ardour Table of Contents')
page = page.replace('{% tree %}', sidebar)
page = page.replace('{{ content }}', toc)
page = page.replace('{% prevnext %}', '')
page = page.replace('{% githubedit %}', '')
page = page.replace('{% themechanger %}', themechanger)
page = page.replace('{% breadcrumbs %}', '')

os.mkdir(global_site_dir + 'toc', 0o775)
tocFile = open(global_site_dir + 'toc/index.html', 'w')
tocFile.write(page)
tocFile.close()

# Create the one-page version of the documentation
onepageFile = open(global_site_dir + 'ardourmanual.html', 'w')
opsidebar = BuildOnePageSidebar(fileStruct) # create the link sidebar
onepage = onepage.replace('{% tree %}', opsidebar)
onepage = onepage.replace('{{ content }}', '') # cleans up the last spaceholder
onepageFile.write(onepage)
onepageFile.close()

if pdf:
	if noisy:
		print('Generating the PDF...')
		import logging
		logger = logging.getLogger('weasyprint')
		logger.addHandler(logging.StreamHandler())

	# Create the PDF version of the documentation
	pdfpage = pdfpage.replace('{% tree %}', opsidebar) # create the TOC
	pdfpage = pdfpage.replace('{{ content }}', '') # cleans up the last spaceholder
	pdfpage = pdfpage.replace('{{ today }}', global_today)
	pdfpage = pdfpage.replace('src="/images/', 'src="images/') # makes images links relative
	pdfpage = pdfpage.replace('url(\'/images/', 'url(\'images/') # CSS images links relative
	# Write it to disk (optional, can be removed)
	pdfpageFile = open(global_site_dir + 'pdf.html', 'w')
	pdfpageFile.write(pdfpage)
	pdfpageFile.close()

	# Generating the actual PDF with weasyprint (https://weasyprint.org/)
	from weasyprint import HTML, __version__
	if float(__version__) < 53.0: # handle an API change
		from weasyprint.fonts import FontConfiguration
	else:
		from weasyprint.text.fonts import FontConfiguration
	
	html_font_config = FontConfiguration()
	doc = HTML(string = pdfpage, base_url = global_site_dir)
	doc.write_pdf(global_site_dir + 'manual.pdf', font_config = html_font_config)

# URI redirects
if os.path.exists(global_redirects_file):
	with open(global_redirects_file) as f:
		cpt = 0;
		for line in f:
			line = line.strip();
			if line == '':
				continue	#empty line
			if line.startswith('//'):
				continue	#comment
			params = line.split('|');
			params[0] = params[0].strip(' \t/')
			params[1] = params[1].strip(' \t')
			# write an HTML the file with a refresh redirect
			os.makedirs(global_site_dir + params[0], 0o775, exist_ok=True)
			destFile = open(global_site_dir + params[0] + '/index.html', 'w')
			newlink = FixInternalLinks(links, '"'+params[1]+'"', global_redirects_file)
			newlink = newlink.strip('"')
			page = '<html><head><meta http-equiv="refresh" content="0; url=' + newlink + '"></head><body><p>The page has moved to:<a href="' + newlink + '">this page</a></p></body></html>'
			destFile.write(page)
			destFile.close()
if noisy:
	print('Generated ' + str(cpt) + ' redirection files.')

if noisy:
	print('Processed ' + str(fileCount) + ' files.')

