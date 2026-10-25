"""Project-authored reader, repacker and verifier for the supplied .NET bundle.

Uses only Python's standard library. Never executes an application or extracts
arbitrary archive paths. The caller pins the original executable by SHA256.
"""
import argparse
import array
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib

MARKER = bytes.fromhex('8b1202b96a612038727b930214d7a03213f5b9e6efae3318ee3b2dce24b36aae')
SOURCE_SHA256 = 'FC4536B88B5B85D8ED2E0EF8270F672C066AE78EC64544AAE265A7DF8F877A22'


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest().upper()


def parse(raw):
    marker = raw.find(MARKER)
    require(marker >= 8, 'Bundle marker missing')
    header = struct.unpack_from('<q', raw, marker - 8)[0]
    require(0 < header < len(raw), 'Invalid bundle header')
    cursor = header

    def read(fmt):
        nonlocal cursor
        count = struct.calcsize(fmt)
        require(cursor + count <= len(raw), 'Truncated bundle')
        values = struct.unpack_from(fmt, raw, cursor)
        cursor += count
        return values[0] if len(values) == 1 else values

    def string():
        nonlocal cursor
        length = 0
        for shift in range(0, 35, 7):
            byte = read('<B')
            length |= (byte & 127) << shift
            if byte < 128:
                break
        else:
            raise ValueError('Invalid string length')
        require(cursor + length <= len(raw), 'Truncated string')
        value = raw[cursor:cursor + length].decode('utf-8')
        cursor += length
        return value

    major, minor, count = read('<IIi')
    require(major == 6 and 0 < count < 10000, 'Unsupported bundle format')
    identity = string()
    locations = read('<qqqqQ')
    entries = []
    names = set()
    for _ in range(count):
        offset, size, compressed = read('<qqq')
        kind = read('<B')
        name = string()
        require(name not in names, 'Duplicate bundle entry')
        names.add(name)
        require(0 <= offset <= len(raw) and 0 <= size < 200_000_000 and 0 <= compressed < 200_000_000, 'Invalid entry size')
        require(offset + (compressed or size) <= len(raw), 'Truncated bundle entry')
        entries.append(dict(offset=offset, size=size, compressed=compressed, kind=kind, name=name))
    return dict(marker=marker, header=header, major=major, minor=minor, bundle_id=identity, locations=locations, entries=entries, end=cursor)


def entry_bytes(raw, entry):
    payload = raw[entry['offset']:entry['offset'] + (entry['compressed'] or entry['size'])]
    if entry['compressed']:
        payload = zlib.decompress(payload, -15)
    require(len(payload) == entry['size'], 'Entry length mismatch')
    return payload


def app_entry(info):
    entries = [entry for entry in info['entries'] if entry['name'] == 'RDCMan.dll']
    require(len(entries) == 1, 'Expected one application assembly')
    return entries[0]


def pe_info(raw):
    require(raw[:2] == b'MZ', 'Invalid executable')
    pe = struct.unpack_from('<I', raw, 0x3c)[0]
    require(raw[pe:pe + 4] == b'PE\0\0', 'Invalid PE header')
    optional = pe + 24
    require(struct.unpack_from('<H', raw, optional)[0] == 0x20b, 'Expected x64 PE32+ executable')
    security = optional + 112 + 4 * 8
    certificate_offset, certificate_size = struct.unpack_from('<II', raw, security)
    return optional, security, certificate_offset, certificate_size


def checksum(raw, optional):
    data = bytearray(raw)
    struct.pack_into('<I', data, optional + 64, 0)
    if len(data) % 2:
        data.append(0)
    words = array.array('H')
    words.frombytes(data)
    if sys.byteorder != 'little':
        words.byteswap()
    value = sum(words)
    value = (value & 0xffff) + (value >> 16)
    value = (value & 0xffff) + (value >> 16)
    return (value + len(raw)) & 0xffffffff


def verify(source, target):
    require(digest(source) == SOURCE_SHA256, 'Unsupported original executable')
    before, after = parse(source), parse(target)
    require((before['major'], before['minor'], before['locations']) == (after['major'], after['minor'], after['locations']), 'Bundle metadata changed')
    require(len(before['entries']) == len(after['entries']) == 262, 'Bundle entry count changed')
    optional, security, cert_offset, cert_size = pe_info(source)
    require(cert_offset >= before['end'] and cert_size > 0 and cert_offset + cert_size <= len(source), 'Invalid source certificate range')
    require(len(target) >= cert_offset and struct.unpack_from('<II', target, security) == (0, 0), 'Modified copy retains invalid signature directory')
    prefix_before = bytearray(source[:cert_offset])
    prefix_after = bytearray(target[:cert_offset])
    # Only the bundle pointer, PE checksum and invalid signature directory differ
    # in the existing host/data prefix. All host code and native resources remain.
    for offset, length in ((before['marker'] - 8, 8), (security, 8), (optional + 64, 4)):
        prefix_before[offset:offset + length] = b'\0' * length
        prefix_after[offset:offset + length] = b'\0' * length
    require(prefix_before == prefix_after, 'Unexpected app-host or existing payload change')
    require(struct.unpack_from('<I', target, optional + 64)[0] == checksum(target, optional), 'Invalid PE checksum')
    unchanged = 0
    for old, new in zip(before['entries'], after['entries']):
        require((old['name'], old['kind']) == (new['name'], new['kind']), 'Bundle entry identity changed')
        if old['name'] != 'RDCMan.dll':
            require(entry_bytes(source, old) == entry_bytes(target, new), 'Bundled dependency changed: ' + old['name'])
            unchanged += 1
    return dict(Passed=True, OriginalSHA256=digest(source), LocalizedSHA256=digest(target), LocalizedAssemblySHA256=digest(entry_bytes(target, app_entry(after))), UnchangedBundledFiles=unchanged, HostAndNativeResourcesUnchanged=True, ModifiedCopyUnsigned=True)


def encoded_string(value):
    data = value.encode('utf-8')
    length = len(data)
    prefix = bytearray()
    while length >= 128:
        prefix.append((length & 127) | 128)
        length >>= 7
    prefix.append(length)
    return prefix + data


def repack(source, payload):
    require(digest(source) == SOURCE_SHA256, 'Unsupported original executable')
    info = parse(source)
    optional, security, cert_offset, cert_size = pe_info(source)
    require(cert_offset >= info['end'] and cert_offset + cert_size <= len(source), 'Invalid source certificate range')
    output = bytearray(source[:cert_offset])
    struct.pack_into('<II', output, security, 0, 0)
    output.extend(b'\0' * ((-len(output)) % 4096))
    app_offset = len(output)
    output.extend(payload)
    output.extend(b'\0' * ((-len(output)) % 8))
    header = len(output)
    identity = hashlib.sha256(source + payload).hexdigest()[:12]
    output.extend(struct.pack('<IIi', info['major'], info['minor'], len(info['entries'])))
    output.extend(encoded_string(identity))
    output.extend(struct.pack('<qqqqQ', *info['locations']))
    for entry in info['entries']:
        if entry['name'] == 'RDCMan.dll':
            offset, size, compressed = app_offset, len(payload), 0
        else:
            offset, size, compressed = entry['offset'], entry['size'], entry['compressed']
        output.extend(struct.pack('<qqqB', offset, size, compressed, entry['kind']))
        output.extend(encoded_string(entry['name']))
    struct.pack_into('<q', output, info['marker'] - 8, header)
    struct.pack_into('<I', output, optional + 64, checksum(output, optional))
    return bytes(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('extract', 'repack', 'verify'))
    parser.add_argument('--source', required=True)
    parser.add_argument('--target')
    parser.add_argument('--assembly')
    parser.add_argument('--references')
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    source = Path(args.source).read_bytes()
    require(digest(source) == SOURCE_SHA256, 'Original SHA256 mismatch')
    if args.operation == 'extract':
        require(args.assembly, 'Assembly output path required')
        payload = entry_bytes(source, app_entry(parse(source)))
        with Path(args.assembly).open('xb') as stream:
            stream.write(payload)
        report = dict(Passed=True, OriginalSHA256=digest(source), OriginalAssemblySHA256=digest(payload))
        if args.references:
            references = Path(args.references)
            references.mkdir(exist_ok=False)
            count = 0
            for entry in parse(source)['entries']:
                name = entry['name']
                # Only root managed assemblies from the pinned original, never
                # arbitrary archive paths. These files are read as metadata.
                if entry['kind'] == 1 and name != 'RDCMan.dll' and name.endswith('.dll') and name == Path(name).name:
                    with (references / name).open('xb') as stream:
                        stream.write(entry_bytes(source, entry))
                    count += 1
            report['MetadataReferenceAssemblies'] = count
    elif args.operation == 'repack':
        require(args.assembly and args.target, 'Assembly and target paths required')
        payload = Path(args.assembly).read_bytes()
        target = repack(source, payload)
        report = verify(source, target)
        require(report['LocalizedAssemblySHA256'] == digest(payload), 'Repacked assembly mismatch')
        with Path(args.target).open('xb') as stream:
            stream.write(target)
    else:
        require(args.target, 'Target path required')
        report = verify(source, Path(args.target).read_bytes())
    Path(args.report).write_text(json.dumps(report, ensure_ascii=True, indent=2), encoding='utf-8')
    print(json.dumps({'Passed': True, 'Operation': args.operation}, ensure_ascii=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
