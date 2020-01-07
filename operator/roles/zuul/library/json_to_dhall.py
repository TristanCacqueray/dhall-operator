#!/usr/bin/env python3
# Copyright 2020 Red Hat, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

import argparse
import json
import subprocess
import sys
from typing import Any, Dict, List, Optional
from ansible.module_utils.basic import AnsibleModule  # type: ignore


def pread(args: List[str], stdin: str) -> str:
    proc = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate(stdin.encode('utf-8'))
    if stderr:
        raise RuntimeError("Command failed: " + stderr.decode('utf-8'))
    return stdout.decode('utf-8')


def generate_ssh_key() -> str:
    return subprocess.Popen(
        ["ssh-keygen", "-f", "/proc/self/fd/1", "-t", "rsa", "-m", "pem", "-N", ""],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE).communicate(
            b'y\n')[0].decode('utf-8').split('(y/n)? ')[1]


def run(template: str, params: Dict[str, Any]) -> str:
    schema = '(' + template + ').Input'
    for input_type in (list(map(lambda x: list(map(str.strip, x.split(':'))), map(
            str.strip, pread(['dhall'], schema).strip()[1:-1].split(','))))):
        input_name = input_type[0]
        if input_name in params:
            continue
        if input_name == 'ssh_key':
            params[input_name] = generate_ssh_key()
            continue
    return pread(['json-to-dhall', schema], json.dumps(params))


def ansible_main():
    module = AnsibleModule(
        argument_spec=dict(
            template=dict(required=True, type='str'),
            name=dict(required=True, type='str'),
            params=dict(type='dict'),
        )
    )

    p = module.params
    params = p.get('params', {})
    if "name" not in params:
        params["name"] = p['name']
    try:
        module.exit_json(changed=True, result=run(p['template'], params))
    except Exception as e:
        module.fail_json(msg="Dhall expression failed:" + str(e))


def cli_main():
    parser = argparse.ArgumentParser()
    parser.add_argument('template')
    parser.add_argument('name')
    parser.add_argument('--params')
    args = parser.parse_args()

    params = json.loads(args.params) if args.params else {}
    if "name" not in params:
        params["name"] = args.name
    print(run(args.template, params))


if __name__ == '__main__':
    if sys.stdin.isatty():
        cli_main()
    else:
        ansible_main()
