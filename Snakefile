"""
Snakefile for doing the higher stages of data processing (everything beyond build_raw)
This includes:
- building the tcm
- dsp parameter generation
- building dsp
- hit pars generation
- building hit
- building evt
- the same for partition level tiers
"""

import pathlib, os, json, sys
import scripts.util as ds
from scripts.util.pars_loading import pars_catalog
from scripts.util.patterns import get_pattern_tier_raw
from scripts.util.utils import (
    subst_vars_in_snakemake_config,
    runcmd,
    config_path,
    chan_map_path,
    filelist_path,
    metadata_path,
)
from datetime import datetime
from collections import OrderedDict

# Set with `snakemake --configfile=/path/to/your/config.json`
# configfile: "have/to/specify/path/to/your/config.json"

check_in_cycle = True

subst_vars_in_snakemake_config(workflow, config)

setup = config["setups"]["l200"]
configs = config_path(setup)
chan_maps = chan_map_path(setup)
meta = metadata_path(setup)
swenv = runcmd(setup)
part = ds.dataset_file(setup, os.path.join(configs, "partitions.json"))
basedir = workflow.basedir


include: "rules/common.smk"
include: "rules/main.smk"


localrules:
    gen_filelist,
    autogen_output,


ds.pars_key_resolve.write_par_catalog(
    ["-*-*-*-cal"],
    os.path.join(pars_path(setup), "pht", "validity.jsonl"),
    get_pattern_tier_raw(setup),
    {"cal": ["par_pht"], "lar": ["par_pht"]},
)


include: "rules/tcm.smk"
include: "rules/dsp.smk"
include: "rules/hit.smk"
include: "rules/pht.smk"
include: "rules/blinding_calibration.smk"


onstart:
    print("Starting workflow")
    shell(f"rm {pars_path(setup)}/dsp/validity.jsonl || true")
    shell(f"rm {pars_path(setup)}/hit/validity.jsonl || true")
    shell(f"rm {pars_path(setup)}/pht/validity.jsonl || true")
    shell(f"rm {pars_path(setup)}/raw/validity.jsonl || true")
    ds.pars_key_resolve.write_par_catalog(
        ["-*-*-*-cal"],
        os.path.join(pars_path(setup), "raw", "validity.jsonl"),
        get_pattern_tier_raw(setup),
        {"cal": ["par_raw"]},
    )
    ds.pars_key_resolve.write_par_catalog(
        ["-*-*-*-cal"],
        os.path.join(pars_path(setup), "dsp", "validity.jsonl"),
        get_pattern_tier_raw(setup),
        {"cal": ["par_dsp"], "lar": ["par_dsp"]},
    )
    ds.pars_key_resolve.write_par_catalog(
        ["-*-*-*-cal"],
        os.path.join(pars_path(setup), "hit", "validity.jsonl"),
        get_pattern_tier_raw(setup),
        {"cal": ["par_hit"], "lar": ["par_hit"]},
    )
    ds.pars_key_resolve.write_par_catalog(
        ["-*-*-*-cal"],
        os.path.join(pars_path(setup), "pht", "validity.jsonl"),
        get_pattern_tier_raw(setup),
        {"cal": ["par_pht"], "lar": ["par_pht"]},
    )


onsuccess:
    print("Workflow finished, no error")
    shell("rm *.gen || true")
    shell(f"rm {filelist_path(setup)}/* || true")


# Placeholder, can email or maybe put message in slack
onerror:
    print("An error occurred :( ")


checkpoint gen_filelist:
    """
    This rule generates the filelist. It is a checkpoint so when it is run it will update
    the dag passed on the files it finds as an output. It does this by taking in the search
    pattern, using this to find all the files that match this pattern, deriving the keys from
    the files found and generating the list of new files needed.
    """
    output:
        os.path.join(filelist_path(setup), "{label}-{tier}.{extension}list"),
    params:
        setup=lambda wildcards: setup,
        search_pattern=lambda wildcards: get_pattern_tier_raw(setup),
        basedir=basedir,
        configs=configs,
        chan_maps=chan_maps,
        blinding=False,
    script:
        "scripts/create_{wildcards.extension}list.py"
