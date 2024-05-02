"""
Snakemake rules for processing pht (partition hit) tier data. This is done in 4 steps:
- extraction of calibration curves(s) for each run for each channel from cal data
- extraction of psd calibration parameters and partition level energy fitting for each channel over whole partition from cal data
- combining of all channels into single pars files with associated plot and results files
- running build hit over all channels using par file
"""

from scripts.util.pars_loading import pars_catalog
from scripts.util.create_pars_keylist import pars_key_resolve
from scripts.util.utils import par_psp_path, par_dsp_path, set_last_rule_name
from scripts.util.patterns import (
    get_pattern_pars_tmp_channel,
    get_pattern_plts_tmp_channel,
    get_pattern_log_channel,
    get_pattern_plts,
    get_pattern_tier,
    get_pattern_pars_tmp,
    get_pattern_log,
    get_pattern_pars,
)

pars_key_resolve.write_par_catalog(
    ["-*-*-*-cal"],
    os.path.join(pars_path(setup), "psp", "validity.jsonl"),
    get_pattern_tier_raw(setup),
    {"cal": ["par_psp"], "lar": ["par_psp"]},
)

psp_rules = {}
for key, dataset in part.datasets.items():
    for partition in dataset.keys():

        rule:
            input:
                dsp_pars=part.get_par_files(
                    f"{par_dsp_path(setup)}/validity.jsonl", partition, key, tier="dsp"
                ),
                dsp_objs=part.get_par_files(
                    f"{par_dsp_path(setup)}/validity.jsonl",
                    partition,
                    key,
                    tier="dsp",
                    name="objects",
                    extension="pkl",
                ),
                dsp_plots=part.get_plt_files(
                    f"{par_dsp_path(setup)}/validity.jsonl", partition, key, tier="dsp"
                ),
            wildcard_constraints:
                channel=part.get_wildcard_constraints(partition, key),
            params:
                datatype="cal",
                channel="{channel}" if key == "default" else key,
                timestamp=part.get_timestamp(
                    f"{par_psp_path(setup)}/validity.jsonl", partition, key, tier="psp"
                ),
            output:
                psp_pars=temp(
                    part.get_par_files(
                        f"{par_psp_path(setup)}/validity.jsonl",
                        partition,
                        key,
                        tier="psp",
                    )
                ),
                psp_objs=temp(
                    part.get_par_files(
                        f"{par_psp_path(setup)}/validity.jsonl",
                        partition,
                        key,
                        tier="psp",
                        name="objects",
                        extension="pkl",
                    )
                ),
                psp_plots=temp(
                    part.get_plt_files(
                        f"{par_psp_path(setup)}/validity.jsonl",
                        partition,
                        key,
                        tier="psp",
                    )
                ),
            log:
                part.get_log_file(
                    f"{par_psp_path(setup)}/validity.jsonl",
                    partition,
                    key,
                    "psp",
                    name="par_psp",
                ),
            group:
                "par-psp"
            resources:
                runtime=300,
            shell:
                "{swenv} python3 -B "
                "{basedir}/../scripts/par_psp.py "
                "--log {log} "
                "--configs {configs} "
                "--datatype {params.datatype} "
                "--timestamp {params.timestamp} "
                "--channel {params.channel} "
                "--in_plots {input.dsp_plots} "
                "--out_plots {output.psp_plots} "
                "--in_obj {input.dsp_objs} "
                "--out_obj {output.psp_objs} "
                "--input {input.dsp_pars} "
                "--output {output.psp_pars} "

        set_last_rule_name(workflow, f"{key}-{partition}-build_par_psp")

        if key in psp_rules:
            psp_rules[key].append(list(workflow.rules)[-1])
        else:
            psp_rules[key] = [list(workflow.rules)[-1]]


# Merged energy and a/e supercalibrations to reduce number of rules as they have same inputs/outputs
# This rule builds the a/e calibration using the calibration dsp files for the whole partition
rule build_par_psp:
    input:
        dsp_pars=get_pattern_pars_tmp_channel(setup, "dsp"),
        dsp_objs=get_pattern_pars_tmp_channel(setup, "dsp", "objects", extension="pkl"),
        dsp_plots=get_pattern_plts_tmp_channel(setup, "dsp"),
    params:
        datatype="cal",
        channel="{channel}",
        timestamp="{timestamp}",
    output:
        psp_pars=temp(get_pattern_pars_tmp_channel(setup, "psp")),
        psp_objs=temp(
            get_pattern_pars_tmp_channel(setup, "psp", "objects", extension="pkl")
        ),
        psp_plots=temp(get_pattern_plts_tmp_channel(setup, "psp")),
    log:
        get_pattern_log_channel(setup, "pars_psp"),
    group:
        "par-psp"
    resources:
        runtime=300,
    shell:
        "{swenv} python3 -B "
        "{basedir}/../scripts/par_psp.py "
        "--log {log} "
        "--configs {configs} "
        "--datatype {params.datatype} "
        "--timestamp {params.timestamp} "
        "--channel {params.channel} "
        "--in_plots {input.dsp_plots} "
        "--out_plots {output.psp_plots} "
        "--in_obj {input.dsp_objs} "
        "--out_obj {output.psp_objs} "
        "--input {input.dsp_pars} "
        "--output {output.psp_pars} "


fallback_psp_rule = list(workflow.rules)[-1]
rule_order_list = []
ordered = OrderedDict(psp_rules)
ordered.move_to_end("default")
for key, items in ordered.items():
    rule_order_list += [item.name for item in items]
rule_order_list.append(fallback_psp_rule.name)
workflow._ruleorder.add(*rule_order_list)  # [::-1]


rule build_pars_psp_objects:
    input:
        lambda wildcards: read_filelist_pars_cal_channel(
            wildcards,
            "psp_objects_pkl",
        ),
    output:
        get_pattern_pars(
            setup,
            "psp",
            name="objects",
            extension="dir",
            check_in_cycle=check_in_cycle,
        ),
    group:
        "merge-hit"
    shell:
        "{swenv} python3 -B "
        "{basedir}/../scripts/merge_channels.py "
        "--input {input} "
        "--output {output} "


rule build_plts_psp:
    input:
        lambda wildcards: read_filelist_plts_cal_channel(wildcards, "psp"),
    output:
        get_pattern_plts(setup, "psp"),
    group:
        "merge-hit"
    shell:
        "{swenv} python3 -B "
        "{basedir}/../scripts/merge_channels.py "
        "--input {input} "
        "--output {output} "


# rule build_pars_psp:
#     input:
#         infiles=lambda wildcards: read_filelist_pars_cal_channel(wildcards, "psp"),
#         plts=get_pattern_plts(setup, "psp"),
#         objects=get_pattern_pars(
#             setup,
#             "psp",
#             name="objects",
#             extension="dir",
#             check_in_cycle=check_in_cycle,
#         ),
#     output:
#         get_pattern_pars(setup, "psp", check_in_cycle=check_in_cycle),
#     group:
#         "merge-hit"
#     shell:
#         "{swenv} python3 -B "
#         f"{basedir}/../scripts/merge_channels.py "
#         "--input {input.infiles} "
#         "--output {output} "


rule build_psp:
    input:
        raw_file=get_pattern_tier_raw(setup),
        pars_file=ancient(
            lambda wildcards: pars_catalog.get_par_file(
                setup, wildcards.timestamp, "psp"
            )
        ),
    params:
        timestamp="{timestamp}",
        datatype="{datatype}",
    output:
        tier_file=get_pattern_tier(setup, "psp", check_in_cycle=check_in_cycle),
        db_file=get_pattern_pars_tmp(setup, "psp_db"),
    log:
        get_pattern_log(setup, "tier_dsp"),
    group:
        "tier-dsp"
    resources:
        runtime=300,
        mem_swap=50,
    shell:
        "{swenv} python3 -B "
        "{basedir}/../scripts/build_dsp.py "
        "--log {log} "
        "--configs {configs} "
        "--datatype {params.datatype} "
        "--timestamp {params.timestamp} "
        "--input {input.raw_file} "
        "--output {output.tier_file} "
        "--db_file {output.db_file} "
        "--pars_file {input.pars_file}"
