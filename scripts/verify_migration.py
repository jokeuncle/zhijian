#!/usr/bin/env python3
"""Exercise packaged CLI migration using disposable libraries, never user data."""
import argparse
import copy
import hashlib
import json
import pathlib
import platform
import re
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=pathlib.Path, default=ROOT / 'build/知间.app/Contents/MacOS/zhijian')
    parser.add_argument('--count', type=int, default=10000)
    parser.add_argument('--report', type=pathlib.Path)
    args = parser.parse_args()
    assert args.count >= 10
    binary = args.binary.resolve()
    report = {'entry_count': args.count, 'platform': platform.platform(),
              'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'profiles': {}, 'checks': [], 'limitations': []}

    with tempfile.TemporaryDirectory(prefix='zhijian-migration-') as folder:
        root = pathlib.Path(folder)

        def cli(db, *command, payload=None, ok=True, seeded=False):
            argv = [str(binary), '--database', str(db)]
            if not seeded:
                argv.append('--no-seed')
            argv.extend(map(str, command))
            measured = platform.system() == 'Darwin'
            started = time.perf_counter()
            result = subprocess.run((['/usr/bin/time', '-l'] if measured else []) + argv,
                                    input=None if payload is None else json.dumps(payload, ensure_ascii=False),
                                    text=True, capture_output=True, timeout=180)
            metrics = {'seconds': round(time.perf_counter() - started, 3)}
            rss = re.search(r'(\d+)\s+maximum resident set size', result.stderr)
            if rss:
                metrics['peak_rss_mb'] = round(int(rss[1]) / 1e6, 2)
            assert (result.returncode == 0) == ok, (command, result.stdout, result.stderr)
            return json.loads(result.stdout), metrics

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False), encoding='utf-8')
            return path

        def exported(db, path):
            _, metrics = cli(db, 'export', path)
            return json.loads(path.read_text()), metrics

        def normalized(archive):
            return {'schemaVersion': archive['schemaVersion'],
                    'entries': sorted(archive['entries'], key=lambda e: e['id']),
                    'collections': sorted(archive['collections'], key=lambda c: c['id'])}

        for profile, repetitions in [('standard', 12), ('long_content', 300)]:
            source, target = root / (profile + '-source.sqlite'), root / (profile + '-target.sqlite')
            entries = [{'id': f'migration-{i}', 'title': f'迁移概念{i:05d}', 'english': f'Migration Concept {i}',
                        'aliases': [f'迁移别名{i}', f'Alias {i}'], 'summary': f'迁移测试解释{i}，包含 Unicode 🧠。',
                        'analogy': '一本随身携带的词典。', 'details': ('迁移内容包含中文、English 和换行。\n' * repetitions),
                        'caveat': '测试内容不代表真实文章。', 'category': f'迁移分类{i % 10}',
                        'kind': 'comparison' if i % 20 == 0 else 'concept', 'sourceTitle': '合成迁移测试笔记',
                        'sourceURL': 'https://example.com/migration', 'sourceExcerpt': '合成摘录',
                        'personalNote': f'个人理解{i}：不能丢失。',
                        'relatedIDs': [f'migration-{(i + 1) % args.count}']} for i in range(args.count)]
            batch = write(root / (profile + '-batch.json'), {'entries': entries, 'collectionTitle': '迁移阅读路径',
                                                          'collectionSubtitle': '严格保留原始顺序'})
            result, setup = cli(source, 'import', batch)
            assert result['created'] == args.count
            del entries
            cli(source, 'update', 'migration-0', '--revision', 1, '--json', '-',
                payload={'favorite': True, 'personalNote': '修改后的个人理解，保留历史。'})
            for i, rating in enumerate([0, 1, 2]):
                cli(source, 'review', f'migration-{i}', '--revision', 2 if i == 0 else 1, '--rating', rating)
            cli(source, 'delete', f'migration-{args.count - 1}', '--revision', 1)
            archive_path = root / (profile + '-backup.json')
            before, export_metrics = exported(source, archive_path)
            assert len(before['entries']) == args.count
            assert before['collections'][0]['entryIDs'] == [f'migration-{i}' for i in range(args.count)]
            imported, import_metrics = cli(target, 'import', archive_path)
            assert imported['created'] == args.count and imported['skipped'] == 0
            after, _ = exported(target, root / (profile + '-restored.json'))
            assert normalized(before) == normalized(after), 'Restored archive differs'
            assert cli(source, 'stats')[0] == cli(target, 'stats')[0]
            assert cli(target, 'list', '--query', 'Migration Concept 0')[0]['total'] == 1
            assert cli(target, 'list', '--query', '修改后的个人理解')[0]['total'] == 1
            repeated, _ = cli(target, 'import', archive_path)
            assert repeated['created'] == 0 and repeated['skipped'] == args.count
            repeated_archive, _ = exported(target, root / 'repeat.json')
            assert normalized(after) == normalized(repeated_archive)
            source_history = cli(source, 'history', 'migration-0')[0]
            target_history = cli(target, 'history', 'migration-0')[0]
            assert len(source_history) == 3 and len(target_history) == 1
            report['profiles'][profile] = {'backup_mb': round(archive_path.stat().st_size / 1e6, 2),
                                           'setup_import': setup, 'export': export_metrics, 'restore': import_metrics,
                                           'all_entry_and_collection_fields_equal': True,
                                           'source_history_count': len(source_history),
                                           'restored_history_count': len(target_history)}
            print(profile + ': ' + json.dumps(report['profiles'][profile], ensure_ascii=False), flush=True)

            if profile != 'standard':
                continue
            # Reject failures after some entries have been processed; preserve existing data.
            small = copy.deepcopy(before)
            small['entries'] = [copy.deepcopy(before['entries'][i]) for i in [3, 4]]
            small['collections'] = []
            for e in small['entries']:
                e['content']['relatedIDs'] = []
            failure_db = root / 'failure.sqlite'
            cli(failure_db, 'create', '--json', '-', payload={'title': '保留哨兵', 'summary': '已有数据'})
            baseline, _ = exported(failure_db, root / 'baseline.json')
            variants = {}
            bad = copy.deepcopy(small); bad['entries'][-1]['content']['title'] = '保留哨兵'; variants['title_conflict'] = bad
            bad = copy.deepcopy(small); bad['entries'][-1]['content']['relatedIDs'] = ['missing-id']; variants['dangling_relation'] = bad
            bad = copy.deepcopy(small); bad['entries'][-1]['revision'] = 0; variants['invalid_revision'] = bad
            bad = copy.deepcopy(small); bad['collections'] = [dict(before['collections'][0], entryIDs=['missing-id'])]; variants['invalid_collection'] = bad
            bad = copy.deepcopy(small); bad['entries'][-1]['id'] = bad['entries'][0]['id']; variants['duplicate_ids'] = bad
            bad = copy.deepcopy(small); bad['schemaVersion'] = 999; variants['unsupported_version'] = bad
            for label, bad in variants.items():
                cli(failure_db, 'import', write(root / (label + '.json'), bad), ok=False)
                unchanged, _ = exported(failure_db, root / 'unchanged.json')
                assert normalized(baseline) == normalized(unchanged), label
                report['checks'].append(label + ': rejected with full rollback')
            truncated = root / 'truncated.json'; truncated.write_text(archive_path.read_text()[:1000])
            cli(failure_db, 'import', truncated, ok=False)
            unchanged, _ = exported(failure_db, root / 'unchanged.json')
            assert normalized(baseline) == normalized(unchanged)
            report['checks'].append('truncated_json: rejected with no changes')
            # Same IDs must preserve local changes, rather than silently replacing them.
            current = cli(target, 'get', 'migration-0')[0]
            cli(target, 'update', 'migration-0', '--revision', current['revision'], '--json', '-', payload={'personalNote': '新电脑修改'})
            cli(target, 'import', archive_path)
            assert cli(target, 'get', 'migration-0')[0]['content']['personalNote'] == '新电脑修改'
            report['checks'].append('same_id: local changes preserved on repeat import')
            seeded_db = root / 'seeded.sqlite'
            initial = cli(seeded_db, 'stats', seeded=True)[0]
            cli(seeded_db, 'import', archive_path, seeded=True)
            seeded_stats = cli(seeded_db, 'stats', seeded=True)[0]
            assert seeded_stats['entries'] == initial['entries'] + args.count - 1
            report['seeded_destination_extra_entries'] = initial['entries']
            report['checks'].append('seeded_destination: initial examples retained, not an exact restore')

        report['limitations'] = ['Historical changes are not exported; restore creates one import history record per entry.',
                                 'Reading position and app preferences are absent from LibraryArchive (source inspection).',
                                 'Native backup selection uses bounded preview and file streaming; pasted/ordinary notes remain capped at 64 MB.',
                                 'Measurements use local packaged CLI and separate temporary libraries, not two physical computers.']
        report['user_library_touched'] = False
    if args.report:
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS migration field equality, repeat import, failure rollback and search; temporary libraries removed.', flush=True)


if __name__ == '__main__':
    main()
