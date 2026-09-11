const assert = require('node:assert/strict');
const { test } = require('node:test');
const { resolvePullRequest, reportBuild } = require('./pr-report.cjs');

function fixture() {
  const run = {
    id: 20, run_attempt: 1, workflow_id: 3, name: 'PR Build',
    path: '.github/workflows/pr-check.yml', event: 'pull_request',
    display_title: 'PR Build #7 (ok-to-build)',
    status: 'completed', conclusion: 'success', repository: { id: 1 },
    head_repository: { id: 2, owner: { login: 'contributor' } },
    head_sha: 'a'.repeat(40), head_branch: 'main',
    pull_requests: [],
  };
  const pr = {
    number: 7, state: 'open', base: { repo: { id: 1 } },
    head: { repo: { id: 2 }, ref: 'main', sha: run.head_sha },
  };
  const state = {
    run, pr, associated: [pr], recent: [run], writes: [],
    jobs: [
      { name: 'check-changes', conclusion: 'success' },
      { name: 'Build packages (core / x86_64)', conclusion: 'success',
        steps: [{ name: 'Build Modified Packages', conclusion: 'success' }] },
    ],
  };
  const github = {
    rest: {
      actions: {
        getWorkflowRun: async () => ({ data: state.run }),
        listWorkflowRuns: async () => ({ data: { workflow_runs: state.recent } }),
        listJobsForWorkflowRun: async () => state.jobs,
      },
      pulls: {
        list: async args => {
          assert.equal(args.head, 'contributor:main');
          assert.equal(args.state, 'open');
          return state.associated;
        },
        get: async () => ({ data: state.pr }),
      },
      issues: Object.fromEntries(['createComment', 'addLabels', 'removeLabel'].map(
        method => [method, async args => state.writes.push({ method, ...args })],
      )),
    },
    paginate: (method, args) => method(args),
  };
  const context = {
    repo: { owner: 'VUP-Linux', repo: 'vup' }, serverUrl: 'https://github.com',
    payload: { repository: { id: 1 }, workflow_run: structuredClone(run) },
  };
  return { state, github, context, core: { info() {} } };
}

test('fork PR with empty run association resolves from GitHub branch and SHA metadata', async () => {
  const f = fixture();
  assert.equal((await resolvePullRequest(f)).pr.number, 7);
});

for (const [name, modify] of [
  ['privileged trigger', f => { f.context.payload.workflow_run.event = 'pull_request_target'; }],
  ['unexpected workflow file', f => { f.state.run.path = '.github/workflows/other.yml'; }],
  ['unrecognized workflow name', f => { f.state.run.name = 'other'; }],
  ['wrong base repository', f => { f.state.pr.base.repo.id = 99; }],
  ['wrong fork', f => { f.state.pr.head.repo.id = 99; }],
  ['wrong branch in the same fork', f => { f.state.pr.head.ref = 'other'; }],
  ['new commit', f => { f.state.pr.head.sha = 'b'.repeat(40); }],
  ['closed PR', f => { f.state.pr.state = 'closed'; }],
  ['ambiguous commit association', f => { f.state.associated.push(f.state.pr); }],
  ['invalid PR number', f => { f.state.associated = [{ number: "7'); throw 1; //" }]; }],
  ['newer attempt', f => { f.state.run.run_attempt = 2; }],
  ['newer build', f => { f.state.recent.push({ ...f.state.run, id: 21 }); }],
]) {
  test(`${name} cannot produce a comment or labels`, async () => {
    const f = fixture();
    modify(f);
    await reportBuild(f);
    assert.deepEqual(f.state.writes, []);
  });
}

test('unrelated label run does not hide a completed build', async () => {
  const f = fixture();
  f.state.recent.push({ ...f.state.run, id: 21, display_title: 'PR Build #7 (bug)' });
  await reportBuild(f);
  assert.ok(f.state.writes.some(write => write.method === 'addLabels'));
});

test('successful compilation is reported for the exact SHA and consumes approval', async () => {
  const f = fixture();
  await reportBuild(f);
  assert.equal(f.state.writes[0].issue_number, 7);
  assert.match(f.state.writes[0].body, /VUP Build Passed/);
  assert.ok(f.state.writes[0].body.includes(f.state.run.head_sha));
  assert.deepEqual(f.state.writes[1].labels, ['build-passed']);
  assert.equal(f.state.writes[2].name, 'ok-to-build');
});

for (const [name, modify] of [
  ['failed build', f => { f.state.run.conclusion = 'failure'; f.state.jobs[1].conclusion = 'failure'; }],
  ['failed setup despite successful report', f => { f.state.jobs[1].conclusion = 'failure'; }],
  ['cancelled build', f => { f.state.run.conclusion = 'cancelled'; }],
  ['missing build jobs', f => { f.state.jobs.pop(); }],
  ['missing selection job', f => { f.state.jobs.shift(); }],
  ['skipped compilation step', f => { f.state.jobs[1].steps[0].conclusion = 'skipped'; }],
]) {
  test(`${name} never adds build-passed`, async () => {
    const f = fixture();
    modify(f);
    await reportBuild(f);
    assert.ok(f.state.writes.some(write => write.method === 'createComment'));
    assert.ok(!f.state.writes.some(write => write.method === 'addLabels'));
    assert.ok(f.state.writes.some(write => write.method === 'removeLabel' && write.name === 'build-passed'));
  });
}

test('a skipped label gate leaves existing labels alone', async () => {
  const f = fixture();
  f.state.jobs[0].conclusion = 'skipped';
  await reportBuild(f);
  assert.deepEqual(f.state.writes, []);
});

test('push during result lookup suppresses all writes', async () => {
  const f = fixture();
  f.github.rest.actions.listJobsForWorkflowRun = async () => {
    f.state.pr.head.sha = 'b'.repeat(40);
    return f.state.jobs;
  };
  await reportBuild(f);
  assert.deepEqual(f.state.writes, []);
});
