#!/usr/bin/python
#
# Small program to 'implode' the master document automagically from separate
# files in the include/ directory.
#
# by James Hammons
# (C) 2017 Underground Software
#

import os
import re
import shutil

lineCount = 0


#
# Parse headers into a dictionary
#
def ParseHeader(fileObj):
	global lineCount
	header = {}

	while (True):
		hdrLine = fileObj.readline().rstrip('\r\n')
		lineCount = lineCount + 1

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
# Check to see if a given file has a header (it shouldn't)
#
def CheckForHeader(fn):
	check = open(fn)

	for line in check:
		if line.startswith('---'):
			check.close()
			return True

	check.close()
	return False


fileCount = 0
delList = []

master = open('master-doc.txt')
firstLine = master.readline().rstrip('\r\n')
master.close()

if firstLine == '<!-- imploded -->':
	print('Master file has already been imploded.')
	exit(0)

if os.rename('master-doc.txt', 'master-doc.bak') == False:
	print('Could not rename master-doc.txt!')
	exit(-1)

master = open('master-doc.bak', 'r')
implode = open('master-doc.txt', 'w')

implode.write('<!-- imploded -->\n')

for line in master:
	lineCount = lineCount + 1

	# Do any header parsing if needed...
	if line.startswith('---'):

		noMove = False
		header = ParseHeader(master)

		# Pull in files and write the result to the master file
		implode.write('\n---\n' + 'title: ' + header['title'] + '\n')

		if header['part'] != 'part':
			if 'menu_title' in header:
				implode.write('menu_title: ' + header['menu_title'] + '\n')

			if 'style' in header:
				implode.write('style: ' + header['style'] + '\n')

			implode.write('file: ' + header['include'] + '\n')

			if ('exclude' in header) and ('include' in header):
				noMove = True
				implode.write('include: ' + header['include'] + '\n')
				implode.write('exclude: yes\n')

		if 'link' in header:
			implode.write('link: ' + header['link'] + '\n')

		if 'uri' in header:
			implode.write('uri: ' + header['uri'] + '\n')

		implode.write('part: ' + header['part'] + '\n' + '---\n')

		# Only parts have no content...
		if header['part'] != 'part':
			if noMove:
				implode.write('\n')
			else:
				fileCount = fileCount + 1
				inclFile = 'include/' + header['include']

				try:
					fromFile = open(inclFile)
				except (FileNotFoundError):
					print('Could not find include file "include/' + header['include'] + '"; aborting!')
					os.remove('master-doc.txt')
					os.rename('master-doc.bak', 'master-doc.txt')
					exit(-1)

#eventually this will go away, as this will never happen again...
				if CheckForHeader(inclFile) == True:

					# Skip the header
					while fromFile.readline().startswith('---') == False:
						pass

					ln = fromFile.readline()

					while fromFile.readline().startswith('---') == False:
						pass

#				shutil.copyfileobj(fromFile, implode)
				# Strip trailing newlines from content...
				tempContent = fromFile.read().rstrip('\r\n')
				implode.write(tempContent + '\n')
				fromFile.close()
				delList.append(inclFile)

master.close()
implode.close()

print('Processed ' + str(lineCount) + ' lines.')
print('Imploded master document from ' + str(fileCount) + ' files.')

# Cleanup after successful implode
os.remove('master-doc.bak')

for name in delList:
	os.remove(name)

