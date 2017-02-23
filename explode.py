#!/usr/bin/python
#
# Small program to 'explode' the master document automagically into separate
# files in the include/ directory.
#
# by James Hammons
# (C) 2017 Underground Software
#

import os
import re
import shutil

lineCount = 0
cleanString = re.compile(r'[^a-zA-Z0-9 \._-]+')


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


fileCount = 0
writingFile = False
toFile = open('master-doc.txt')
toFile.close()
filenames = []


master = open('master-doc.txt')
firstLine = master.readline().rstrip('\r\n')
master.close()

if firstLine == '<!-- exploded -->':
	print('Master file has already been exploded.')
	exit(0)

if os.rename('master-doc.txt', 'master-doc.bak') == False:
	print('Could not rename master-doc.txt!')
	exit(-1)

master = open('master-doc.bak', 'r')
explode = open('master-doc.txt', 'w')

explode.write('<!-- exploded -->\n')

for line in master:
	lineCount = lineCount + 1

	# Do any header parsing if needed...
	if line.startswith('---'):

		# Close any open file from the previous header
		if (writingFile):
			toFile.close()
			writingFile = False

		noMove = False
		header = ParseHeader(master)

		# Make sure the filename we're making is unique...
		basename = MakeFilename(header['title'])
		inclFile = basename + '.html'

		if 'file' in header:
			inclFile = header['file']
		else:
			suffix = 1

			while inclFile in filenames:
				suffix = suffix + 1
				inclFile = basename + '_' + str(suffix) + '.html'

		# Find all files in the master file and write them out to include/,
		# while removing it from the master file.
		explode.write('\n---\n' + 'title: ' + header['title'] + '\n')

		if header['part'] != 'part':
			if 'menu_title' in header:
				explode.write('menu_title: ' + header['menu_title'] + '\n')

			if 'style' in header:
				explode.write('style: ' + header['style'] + '\n')

			if 'include' in header:
				noMove = True
				explode.write('include: ' + header['include'] + '\n')
				explode.write('exclude: yes\n')
				filenames.append(header['include'])
			else:
				explode.write('include: ' + inclFile + '\n')
				filenames.append(inclFile)

		if 'link' in header:
			explode.write('link: ' + header['link'] + '\n')

		if 'uri' in header:
			explode.write('uri: ' + header['uri'] + '\n')

		explode.write('part: ' + header['part'] + '\n' + '---\n')

		# Only parts have no content...
		if header['part'] != 'part':
			if noMove:
				explode.write('\n')
			else:
				fileCount = fileCount + 1

				toFile = open('include/' + inclFile, 'w')
				writingFile = True

	else:
		if writingFile:
			toFile.write(line)

master.close()
explode.close()

print('Processed ' + str(lineCount) + ' lines.')
print('Exploded master document into ' + str(fileCount) + ' files.')

os.remove('master-doc.bak')

