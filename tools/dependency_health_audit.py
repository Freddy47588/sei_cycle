"""Audit pub.dev metadata for all hosted versions locked by this project (stdlib only)."""
import argparse
import concurrent.futures
import datetime
import json
import pathlib
import re
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/dependency-health.json')
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    lock = (root / 'pubspec.lock').read_text(encoding='utf-8')
    entries = re.findall(r'^  (\w+):\n(.*?)(?=^  \w+:|^sdks:)', lock, re.M | re.S)

    def check(entry):
        name, block = entry
        if 'source: hosted' not in block:
            return None
        version = re.search(r'    version: "?([^"\n]+)', block).group(1)
        result = {'package': name, 'locked': version,
                  'direct': 'dependency: "direct' in block,
                  'source': f'https://pub.dev/api/packages/{name}'}
        try:
            with urllib.request.urlopen(result['source'], timeout=45) as response:
                package = json.load(response)
            locked = next(v for v in package['versions'] if v['version'] == version)
            spec = locked['pubspec']
            result.update(discontinued=package.get('isDiscontinued', False),
                          replacedBy=package.get('replacedBy'),
                          retracted=locked.get('retracted', False),
                          latest=package['latest']['version'],
                          latestPublished=package['latest']['published'],
                          environment=spec.get('environment'),
                          repository=spec.get('repository') or spec.get('homepage'))
        except Exception as error:
            result['error'] = str(error)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as executor:
        packages = [row for row in executor.map(check, entries) if row]
    report = {'checkedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'scope': 'Hosted Dart package metadata; not an audit of every dependency API or native artifact.',
              'packages': packages}
    repositories = {}
    for package in packages:
        if package['direct']:
            match = re.search(r'github.com/([^/]+/[^/#]+)', package.get('repository') or '')
            if match:
                repositories.setdefault(match.group(1).removesuffix('.git'), []).append(package['package'])

    def check_repository(entry):
        repository, names = entry
        source = 'https://api.github.com/repos/' + repository
        result = {'repository': 'https://github.com/' + repository, 'packages': names, 'source': source}
        try:
            request = urllib.request.Request(source, headers={'User-Agent': 'SeiCycle-dependency-audit'})
            with urllib.request.urlopen(request, timeout=30) as response:
                metadata = json.load(response)
            result.update(archived=metadata['archived'], disabled=metadata['disabled'], pushedAt=metadata['pushed_at'])
        except Exception as error:
            result['error'] = str(error)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        report['directRepositoryChecks'] = list(executor.map(check_repository, repositories.items()))
    output = root / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    flagged = [p for p in packages if p.get('error') or p.get('discontinued') or p.get('retracted')]
    flagged.extend(p for p in report['directRepositoryChecks'] if p.get('error') or p.get('archived') or p.get('disabled'))
    print(json.dumps({'hostedChecked': len(packages), 'flags': flagged, 'output': str(output)}))
    return 1 if flagged else 0


if __name__ == '__main__':
    raise SystemExit(main())
