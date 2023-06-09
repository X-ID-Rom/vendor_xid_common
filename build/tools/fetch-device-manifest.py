#!/usr/bin/env python
# Copyright (C) 2012-2013, The CyanogenMod Project
#           (C) 2017-2018,2020-2021, The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


from __future__ import print_function

import base64
import glob
import json
import netrc
import os
import re
import sys
import platform
import json
try:
  # For python3
  import urllib.error
  import urllib.parse
  import urllib.request
except ImportError:
  # For python2
  import imp
  import urllib2
  import urlparse
  urllib = imp.new_module('urllib')
  urllib.error = urllib2
  urllib.parse = urlparse
  urllib.request = urllib2

from xml.etree import ElementTree

py_ver = platform.python_version_tuple()
py_major_ver = int(py_ver[0])
if py_major_ver == 2 :
    print("\033[0;32m"+ "WARNING: Python2 is deprecated" +"\033[0m")

supported_device_manifest = "https://raw.githubusercontent.com/X-ID-Rom/devices/main/supported.xml"
devices_repo_manifest_template = "https://raw.githubusercontent.com/X-ID-Rom/devices/main/devices/"
git_default_revision = "thirteen"

local_manifests = r'.repo/local_manifests'
if not os.path.exists(local_manifests): os.makedirs(local_manifests)

product = sys.argv[1]

if len(sys.argv) > 2:
    depsonly = sys.argv[2]
else:
    depsonly = None

try:
    device = product[product.index("_") + 1:]
except:
    device = product

if not depsonly:
    print("Device %s not found. Attempting to retrieve device repository from Github." % device)

supported_devices = []

def fetch_all_supported_devices():
    githubreq = urllib.request.Request(supported_device_manifest)
    reqRes = urllib.request.urlopen(githubreq).read().decode()
    print(reqRes)
    try:
        result = ElementTree.fromstring(reqRes)
    except urllib.error.URLError:
        print("Failed to fetch data from GitHub")
        sys.exit(1)
    except ValueError:
        print("Failed to parse return data from GitHub")
        sys.exit(1)

    for res in result.findall('./devices/device'):
        # print()
        supported_devices.append((res.attrib["codename"], res.attrib["manufacturer"], res.attrib["relativePath"]))

def indent(elem, level=0):
    i = "\n" + level*"  "
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = i + "  "
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
        for elem in elem:
            indent(elem, level+1)
        if not elem.tail or not elem.tail.strip():
            elem.tail = i
    else:
        if level and (not elem.tail or not elem.tail.strip()):
            elem.tail = i

def has_branch(branches, revision):
    return revision in [branch['name'] for branch in branches]

def fetch_current_branch(repo_name):
    print("Default revision: %s" % git_default_revision)
    print("Checking branch info")

    githubreq = urllib.request.Request("https://api.github.com/repos/X-ID-Rom/" + repo_name + "/branches")
    result = json.loads(urllib.request.urlopen(githubreq).read().decode())
    if has_branch(result, git_default_revision):
        return git_default_revision

    # fallbacks = [ get_default_revision_no_minor() ]
    # if os.getenv('ROOMSERVICE_BRANCHES'):
        # fallbacks += list(filter(bool, os.getenv('ROOMSERVICE_BRANCHES').split(' ')))

    # for fallback in fallbacks:
    #     if has_branch(result, fallback):
    #         print("Using fallback branch: %s" % fallback)
    #         return fallback

    print("Default revision %s not found in %s. Bailing." % (git_default_revision, repo_name))
    print("Branches found:")
    for branch in [branch['name'] for branch in result]:
        print(branch)
    print("Use the ROOMSERVICE_BRANCHES environment variable to specify a list of fallback branches.")
    sys.exit()


def get_manifest_path():
    '''Find the current manifest path
    In old versions of repo this is at .repo/manifest.xml
    In new versions, .repo/manifest.xml includes an include
    to some arbitrary file in .repo/manifests'''

    m = ElementTree.parse(".repo/manifest.xml")
    try:
        m.findall('default')[0]
        return '.repo/manifest.xml'
    except IndexError:
        return ".repo/manifests/{}".format(m.find("include").get("name"))

def is_in_manifest(projectpath, manifest = ".repo/local_manifests/*.xml"):
    for path in glob.glob(manifest):
        try:
            lm = ElementTree.parse(path)
            lm = lm.getroot()
        except:
            lm = ElementTree.Element("manifest")

        for localpath in lm.findall("project"):
            if localpath.get("path") == projectpath:
                return True

    # Search in main manifest, too
    try:
        lm = ElementTree.parse(get_manifest_path())
        lm = lm.getroot()
    except:
        lm = ElementTree.Element("manifest")

    for localpath in lm.findall("project"):
        if localpath.get("path") == projectpath:
            return True

    # ... and don't forget the lineage snippet
    try:
        lm = ElementTree.parse(".repo/manifests/los-additional.xml")
        lm = lm.getroot()
    except:
        lm = ElementTree.Element("manifest")

    for localpath in lm.findall("project"):
        if localpath.get("path") == projectpath:
            return True

    return False

def update_local_manifest(repo_name, repo_target, repo_revision):
    xml_location = '.repo/local_manifests/roomservice_'+ device +'.xml'
    try:
        lm = ElementTree.parse(xml_location)
        lm = lm.getroot()
    except:
        lm = ElementTree.Element("manifest")

    print('Checking if %s is fetched from %s' % (repo_target, repo_name))
        
    if is_in_manifest(repo_target) == False:
        print('Adding dependency: X-ID-Rom/%s -> %s' % (repo_name, repo_target))
        project = ElementTree.Element("project", attrib = {
            "path": repo_target,
            "remote": "github",
            "name": "X-ID-Rom/%s" % repo_name,
            "revision": repo_revision 
        })
        lm.append(project)

        indent(lm, 0)
        raw_xml = ElementTree.tostring(lm).decode()
        raw_xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + raw_xml

        f = open(xml_location, 'w')
        f.write(raw_xml)
        f.close()
    else: 
        print('LineageOS/%s already fetched to %s' % (repo_name, repo_target))

def fetch_dependencies(repo_path):
    print('Looking for dependencies in %s' % repo_path)
    dependencies_path = repo_path + '/xid.dependencies'
    syncable_repos = []
    verify_repos = []

    if os.path.exists(dependencies_path):
        dependencies_file = open(dependencies_path, 'r')
        dependencies = json.loads(dependencies_file.read())
        fetch_list = []

        for dependency in dependencies:
            if not is_in_manifest(dependency['target_path']):
                if 'branch' not in dependency:
                    dependency['branch'] = fetch_current_branch(dependency['repository'])
                
                syncable_repos.append(dependency['target_path'])
                fetch_list.append(dependency)
            verify_repos.append(dependency['target_path'])

            if not os.path.isdir(dependency['target_path']):
                syncable_repos.append(dependency['target_path'])

        dependencies_file.close()

        if len(fetch_list) > 0:
            print('Adding dependencies to manifest')
            for depends in fetch_list:
                update_local_manifest(depends["repository"], dependency['target_path'], dependency['branch'])
    else:
        print('%s has no additional dependencies.' % repo_path)

    if len(syncable_repos) > 0:
        print('Syncing dependencies')
        os.system('repo sync --force-sync -j$(nproc --all) %s' % ' '.join(syncable_repos))

    for deprepo in verify_repos:
        fetch_dependencies(deprepo)

def get_from_manifest(devicename):
    for path in glob.glob(".repo/local_manifests/roomservice_"+ devicename +".xml"):
        try:
            lm = ElementTree.parse(path)
            lm = lm.getroot()
        except:
            lm = ElementTree.Element("manifest")

        for localpath in lm.findall("project"):
            if re.search("android_device_.*_%s$" % device, localpath.get("name")):
                return localpath.get("path")

    return None

def fetch_deviceinfo(manufacturer = "unknown", codename = "unknown"):
    deviceManifestUrl = devices_repo_manifest_template + manufacturer + "/" + codename + ".xml"
    githubreq = urllib.request.Request(deviceManifestUrl)
    reqRes = urllib.request.urlopen(githubreq).read().decode()

    try:
        result = ElementTree.fromstring(reqRes)
    except urllib.error.URLError:
        print("Failed to fetch data from GitHub")
        sys.exit(1)
    except ValueError:
        print("Failed to parse return data from GitHub")
        sys.exit(1)


    return {
        "revision": result.find("latestBranch").text,
        "repo_location": result.find("githubRemote").text,
        "device_path": result.find("devicePath").text
    }



def fetch_best_branches(manufacturer = "unknown", codename = "unknown"):
    return fetch_deviceinfo(manufacturer, codename)["revision"]

if depsonly:
    repo_path = get_from_manifest(device)
    if repo_path:
        fetch_dependencies(repo_path)
    else:
        print("Trying dependencies-only mode on a non-existing device tree?")

    sys.exit()

else:
    fetch_all_supported_devices()
    for all_device in supported_devices:
        if(re.match(device, all_device[0])):
            codename = all_device[0]
            manufacturer = all_device[1]
            print("Found repository: %s" % codename)
            print("Device Manufacturer: %s" % manufacturer)
            
            revision = fetch_best_branches(manufacturer, codename)
            deviceinfo = fetch_deviceinfo(manufacturer, codename)
            update_local_manifest(deviceinfo["repo_location"], deviceinfo["device_path"], revision)
            print("Syncing repository to retrieve project.")
            os.system('repo sync --force-sync %s' % deviceinfo["device_path"])
            print("Repository synced!")

            fetch_dependencies(deviceinfo["device_path"])
            print("Done")
            sys.exit()
        #     os.system('repo sync --force-sync %s' % repo_path)
        #     print("Repository synced!")
        # sys.exit(0)
        # print(device)
        # if re.match(r"^android_device_[^_]*_" + device + "$", repo_name):
        #     print("Found repository: %s" % repo_name)
            
        #     manufacturer = repo_name.replace("android_device_", "").replace("_" + device, "")
        #     repo_path = "device/%s/%s" % (manufacturer, device)
        #     revision = get_default_or_fallback_revision(repo_name)

        #     device_repository = {'repository':repo_name,'target_path':repo_path,'branch':revision}
        #     add_to_manifest([device_repository])

        #     print("Syncing repository to retrieve project.")
        #     os.system('repo sync --force-sync %s' % repo_path)
        #     print("Repository synced!")

      

print("Repository for %s not found in the repository list. If this is in error, you may need to manually add it to your local_manifests/roomservice.xml." % device)
