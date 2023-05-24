# -*- coding: utf-8 -*-
#
# Copyright (C) 2015 Oliver Schulz <oschulz@mpp.mpg.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

from collections import namedtuple
import bisect
import types
import collections
import json
import copy
import os
from string import Template
from .utils import *

class Props():
    @staticmethod
    def read_from(sources):
        def read_impl(sources):
            if isinstance(sources, str):
                file_name = sources
                with open(file_name, 'r') as file:
                    result = json.load(file)
                    return result
            elif isinstance(sources, list):
                result = {}
                for p in map(read_impl, sources):
                    Props.add_to(result, p)
                return result
            else:
                raise ValueError("Can't run Props.read_from on sources-value of type {t}".format(t = type(sources)))

        result = read_impl(sources)
        return result

    @staticmethod
    def add_to(props_a, props_b):
        a = props_a
        b = props_b

        for key in b:
            if key in a:
                if isinstance(a[key], dict) and isinstance(b[key], dict):
                    Props.add_to(a[key], b[key])
                elif a[key] != b[key]:
                    a[key] = copy.copy(b[key])
            else:
                a[key] = copy.copy(b[key])

class PropsStream():
    @staticmethod
    def get(value):
        if isinstance(value, str):
            return PropsStream.read_from(value)
        elif isinstance(value, collections.Sequence) or isinstance(value, types.GeneratorType):
            return value
        else:
            raise ValueError("Can't get PropsStream from value of type {t}".format(t = type(source)))


    @staticmethod
    def read_from(file_name):
        with open(file_name, 'r') as file:
            for json_str in file:
                yield json.loads(json_str)

class CalibCatalog(namedtuple('CalibCatalog', ['entries'])):
    __slots__ = ()

    class Entry(namedtuple('Entry', ['valid_from','file'])):
        __slots__ = ()

    @staticmethod
    def read_from(file_name):
        entries = {}

        for props in PropsStream.get(file_name):
            timestamp = props["valid_from"]
            if props.get("category") is None:
                system = "all"
            else:
                system = props["category"]
            file_key = props["apply"]
            if system not in entries:
                entries[system] = []
            entries[system].append(CalibCatalog.Entry(unix_time(timestamp),file_key))

        for system in entries:
            entries[system] = sorted(
                entries[system],
                key = lambda entry: entry.valid_from
            )
        return CalibCatalog(entries)


    def calib_for(self, timestamp, category="all", allow_none = False):
        if category in self.entries:
            valid_from = [ entry.valid_from for entry in self.entries[category]]
            pos = bisect.bisect_right(valid_from, unix_time(timestamp))
            if pos > 0:
                return self.entries[category][pos - 1].file
            else:
                if allow_none: return None
                else: raise RuntimeError(f'No valid calibration found for timestamp: {timestamp}, category: {category}')
        else:
            if allow_none: return None
            else: raise RuntimeError(f'No calibrations found for category: {category}')
    
    @staticmethod
    def get_calib_files(catalog_file, timestamp, category="all"):
        catalog = CalibCatalog.read_from(catalog_file)
        return CalibCatalog.calib_for(catalog,timestamp, category)
    