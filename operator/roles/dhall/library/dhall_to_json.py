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
from typing import Any
from ansible.module_utils.basic import AnsibleModule  # type: ignore


def run(expression: str) -> Any:
    proc = subprocess.Popen(
        ['dhall-to-json', '--omit-empty', '--explain'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = proc.communicate(expression.encode('utf-8'))
    if stderr:
        return dict(failed=True, msg=stderr.decode('utf-8'))
    result = dict(result=json.loads(stdout.decode('utf-8')))
    result['changed'] = True
    return result


def ansible_main():
    module = AnsibleModule(
        argument_spec=dict(
            expression=dict(required=True, type='str'),
        )
    )

    p = module.params
    result = run(p['expression'])
    if result.get('failed'):
        module.fail_json(msg="Dhall expression failed:" + result['msg'])
    module.exit_json(**result)


def cli_main():
    parser = argparse.ArgumentParser()
    parser.add_argument('expression')
    args = parser.parse_args()

    print(run(args.expression))


if __name__ == '__main__':
    if sys.stdin.isatty():
        cli_main()
    else:
        ansible_main()
