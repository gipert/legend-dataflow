"""
This module creates the validity files used for determining the time validity of data
"""

import glob
import json
import os
import pathlib
import re
import warnings
from typing import ClassVar

import snakemake as smk

from .FileKey import FileKey, ProcessingFileKey
from .patterns import par_validity_pattern


class pars_key_resolve:
    name_dict: ClassVar[dict] = {"cal": ["par_dsp", "par_hit"], "lar": ["par_dsp", "par_hit"]}

    def __init__(self, valid_from, category, apply):
        self.valid_from = valid_from
        self.category = category
        self.apply = apply

    def __str__(self):
        return f"{self.__dict__}"

    def get_json(self):
        return json.dumps(self.__dict__)

    @classmethod
    def from_filekey(cls, filekey, name_dict):
        return cls(
            filekey.timestamp,
            "all",
            filekey.get_path_from_filekey(
                par_validity_pattern(), processing_step=name_dict, ext="json"
            ),
        )

    @staticmethod
    def write_to_jsonl(file_names, path):
        with open(path, "w") as of:
            for file_name in file_names:
                of.write(f"{file_name.get_json()}\n")

    @staticmethod
    def match_keys(key1, key2):
        if (
            key1.experiment == key2.experiment
            and key1.period == key2.period
            and key1.run == key2.run
            and key1.datatype == key2.datatype
        ):
            if key1.get_unix_timestamp() < key2.get_unix_timestamp():
                return key1
            else:
                return key2
        else:
            return key2

    @staticmethod
    def generate_par_keylist(keys):
        keylist = []
        keys = sorted(keys, key=FileKey.get_unix_timestamp)
        keylist.append(keys[0])
        for key in keys[1:]:
            matched_key = pars_key_resolve.match_keys(keylist[-1], key)
            if matched_key not in keylist:
                keylist.append(matched_key)
            else:
                pass
        return keylist

    @staticmethod
    def match_entries(entry1, entry2):
        datatype2 = ProcessingFileKey.get_filekey_from_filename(entry2.apply[0]).datatype
        for entry in entry1.apply:
            if ProcessingFileKey.get_filekey_from_filename(entry).datatype == datatype2:
                pass
            else:
                entry2.apply.append(entry)

    @staticmethod
    def match_all_entries(entrylist, name_dict):
        out_list = []
        out_list.append(pars_key_resolve.from_filekey(entrylist[0], name_dict))
        for entry in entrylist[1:]:
            new_entry = pars_key_resolve.from_filekey(entry, name_dict)
            pars_key_resolve.match_entries(out_list[-1], new_entry)
            out_list.append(new_entry)
        return out_list

    @staticmethod
    def get_keys(keypart, search_pattern):
        d = FileKey.parse_keypart(keypart)
        try:
            tier_pattern_rx = re.compile(smk.io.regex_from_filepattern(search_pattern))
        except AttributeError:
            tier_pattern_rx = re.compile(smk.io.regex(search_pattern))
        fn_glob_pattern = smk.io.expand(search_pattern, **d._asdict())[0]
        files = glob.glob(fn_glob_pattern)
        keys = []
        for f in files:
            m = tier_pattern_rx.match(f)
            if m is not None:
                d = m.groupdict()
                key = FileKey(**d)
                keys.append(key)
        return keys

    @staticmethod
    def write_par_catalog(keypart, filename, search_patterns, name_dict):
        if isinstance(keypart, str):
            keypart = [keypart]
        if isinstance(search_patterns, str):
            search_patterns = [search_patterns]
        keylist = []
        for search_pattern in search_patterns:
            for keypar in keypart:
                keylist += pars_key_resolve.get_keys(keypar, search_pattern)
        if len(keylist) != 0:
            keys = sorted(keylist, key=FileKey.get_unix_timestamp)
            keylist = pars_key_resolve.generate_par_keylist(keys)

            entrylist = pars_key_resolve.match_all_entries(keylist, name_dict)
            pathlib.Path(os.path.dirname(filename)).mkdir(parents=True, exist_ok=True)
            pars_key_resolve.write_to_jsonl(entrylist, filename)
        else:
            msg = "No Keys found"
            warnings.warn(msg, stacklevel=0)
            entrylist = [pars_key_resolve("00000000T000000Z", "all", [])]
            pars_key_resolve.write_to_jsonl(entrylist, filename)
