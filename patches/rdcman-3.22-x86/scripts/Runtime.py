"""Extract the pinned Microsoft x86 VC runtime without running its installer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

CONFIG = json.loads((Path(__file__).resolve().parent.parent / 'patch.json').read_text(encoding='utf-8-sig'))['nativeRuntime']


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest().upper()


def require_x86(data):
    require(data[:2] == b'MZ', 'Runtime payload is not a PE file')
    pe = struct.unpack_from('<I', data, 0x3c)[0]
    require(data[pe:pe + 4] == b'PE\0\0', 'Runtime PE header missing')
    require(struct.unpack_from('<H', data, pe + 4)[0] == 0x14c and struct.unpack_from('<H', data, pe + 24)[0] == 0x10b, 'Runtime payload is not x86 PE32')


def verify(directory):
    rows = []
    for expected in CONFIG['files']:
        name = expected['name']
        require(name == Path(name).name, 'Invalid runtime filename')
        data = (directory / name).read_bytes()
        require(digest(data) == expected['sha256'], 'Runtime SHA256 mismatch: ' + name)
        require_x86(data)
        rows.append(dict(Name=name, SHA256=expected['sha256'], Bytes=len(data), Architecture='x86'))
    return dict(Passed=True, Version=CONFIG['version'], Files=rows, InstallerExecuted=False, SystemFilesModified=False)


def expand(cabinet, destination):
    destination.mkdir(exist_ok=False)
    executable = Path(os.environ['SystemRoot']) / 'System32/expand.exe'
    result = subprocess.run([str(executable), '-F:*', str(cabinet), str(destination)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    require(result.returncode == 0, 'Windows cabinet extraction failed')


def extract(package, directory, work):
    raw = package.read_bytes()
    require(digest(raw) == CONFIG['packageSHA256'], 'Microsoft runtime package SHA256 mismatch')
    require(not directory.exists(), 'Runtime output directory already exists')
    work.mkdir(exist_ok=False)
    position = 0
    containers = []
    while True:
        offset = raw.find(b'MSCF', position)
        if offset < 0:
            break
        position = offset + 4
        if offset + 36 > len(raw):
            continue
        length = struct.unpack_from('<I', raw, offset + 8)[0]
        files_offset = struct.unpack_from('<I', raw, offset + 16)[0]
        if 36 < length <= len(raw) - offset and 36 <= files_offset < length:
            cabinet = work / ('container-' + str(len(containers)) + '.cab')
            cabinet.write_bytes(raw[offset:offset + length])
            containers.append(cabinet)
    require(len(containers) == 2, 'Unexpected pinned installer layout')
    for index, cabinet in enumerate(containers):
        destination = work / ('container-' + str(index))
        expand(cabinet, destination)
        for child_index, child in enumerate(list(destination.iterdir())):
            if child.is_file() and child.read_bytes()[:4] == b'MSCF':
                expand(child, work / ('payload-' + str(index) + '-' + str(child_index)))
    directory.mkdir(exist_ok=False)
    for expected in CONFIG['files']:
        candidates = [path for path in work.rglob(expected['name'] + '_x86') if path.is_file()]
        require(len(candidates) == 1, 'Pinned runtime payload missing or duplicated: ' + expected['name'])
        require(digest(candidates[0].read_bytes()) == expected['sha256'], 'Extracted runtime payload hash mismatch')
        shutil.copyfile(candidates[0], directory / expected['name'])
    return verify(directory)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('extract', 'verify'))
    parser.add_argument('--package')
    parser.add_argument('--directory', required=True)
    parser.add_argument('--work')
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    if args.operation == 'extract':
        require(args.package and args.work, 'Package and work paths are required')
        report = extract(Path(args.package), Path(args.directory), Path(args.work))
    else:
        report = verify(Path(args.directory))
    Path(args.report).write_text(json.dumps(report, ensure_ascii=True, indent=2), encoding='utf-8')
    print(json.dumps(dict(Passed=True, Files=len(report['Files']), Version=report['Version'])))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
