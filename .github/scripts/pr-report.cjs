// Run only from the trusted default-branch checkout in VUP Bot.
const workflowPaths = {
  'PR Build': '.github/workflows/pr-check.yml',
  'Template Check': '.github/workflows/template-check.yml',
  'PR Title Check': '.github/workflows/pr-title-check.yml',
};

async function resolvePullRequest({ github, context, core }) {
  const eventRun = context.payload.workflow_run;
  if (!eventRun || eventRun.event !== 'pull_request') return null;

  const { data: run } = await github.rest.actions.getWorkflowRun({
    ...context.repo, run_id: eventRun.id,
  });
  if (run.event !== 'pull_request' || run.status !== 'completed' ||
      run.repository.id !== context.payload.repository.id ||
      !Object.values(workflowPaths).includes(run.path) ||
      run.run_attempt !== eventRun.run_attempt ||
      !/^[a-f0-9]{40}$/.test(run.head_sha)) {
    core.info('Ignoring an unexpected or superseded workflow run.');
    return null;
  }

  // Fork runs often have an empty pull_requests array, and the base repo's
  // commit association API can also return nothing for a fork-only commit.
  // Find the PR by its fork/branch, then verify the exact SHA below.
  const candidates = run.pull_requests.length ? run.pull_requests :
    await github.paginate(github.rest.pulls.list, {
      ...context.repo, state: 'open',
      head: `${run.head_repository.owner.login}:${run.head_branch}`, per_page: 100,
    });
  const matches = [];
  for (const candidate of candidates) {
    if (!Number.isSafeInteger(candidate.number) || candidate.number <= 0) continue;
    const { data: pr } = await github.rest.pulls.get({
      ...context.repo, pull_number: candidate.number,
    });
    if (pr.state === 'open' && pr.base.repo.id === run.repository.id &&
        pr.head.repo?.id === run.head_repository.id &&
        pr.head.ref === run.head_branch && pr.head.sha === run.head_sha) {
      matches.push(pr);
    }
  }
  if (matches.length !== 1) {
    core.info('No unique open PR still points to the built commit.');
    return null;
  }

  // A previous run/attempt must not override the result of a newer build.
  const { data: recent } = await github.rest.actions.listWorkflowRuns({
    ...context.repo, workflow_id: run.workflow_id, head_sha: run.head_sha,
    event: 'pull_request', per_page: 100,
  });
  const latest = recent.workflow_runs
    .filter(item => item.head_repository.id === run.head_repository.id &&
      item.head_branch === run.head_branch &&
      (run.path !== workflowPaths['PR Build'] || item.display_title === run.display_title))
    .sort((a, b) => b.id - a.id)[0];
  if (!latest || latest.id !== run.id || latest.run_attempt !== run.run_attempt) {
    core.info('A newer workflow run exists for this commit.');
    return null;
  }
  return { pr: matches[0], run };
}

async function removeLabel(github, repo, number, name) {
  try {
    await github.rest.issues.removeLabel({ ...repo, issue_number: number, name });
  } catch (error) {
    if (error.status !== 404) throw error;
  }
}

async function reportBuild({ github, reader = github, context, core }) {
  const resolved = await resolvePullRequest({ github: reader, context, core });
  if (!resolved || resolved.run.path !== workflowPaths['PR Build']) return;
  const { run, pr } = resolved;
  const jobs = await reader.paginate(reader.rest.actions.listJobsForWorkflowRun, {
    ...context.repo, run_id: run.id, filter: 'latest', per_page: 100,
  });
  const selection = jobs.find(job => job.name === 'check-changes');
  // Adding an unrelated label creates a skipped run; it has no build result.
  if (selection?.conclusion === 'skipped') return;
  const builds = jobs.filter(job => job.name.startsWith('Build packages ('));
  const passed = run.conclusion === 'success' &&
    selection?.conclusion === 'success' && builds.length > 0 &&
    builds.every(job => job.conclusion === 'success' &&
      job.steps?.some(step => step.name === 'Build Modified Packages' &&
        step.conclusion === 'success'));
  const noBuild = run.conclusion === 'success' &&
    selection?.conclusion === 'success' && builds.every(job => job.conclusion === 'skipped');
  const title = passed ? ':white_check_mark: VUP Build Passed' :
    noBuild ? ':information_source: No packages built' : ':x: VUP Build Failed';
  const detail = passed ? `${builds.length} package build job(s) completed successfully.` :
    noBuild ? 'No changed packages were selected for a build.' :
      'Compilation or build setup did not complete successfully.';
  const runUrl = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${run.id}`;

  // Recheck after fetching jobs so an intervening push cannot get this result.
  const { data: current } = await github.rest.pulls.get({
    ...context.repo, pull_number: pr.number,
  });
  if (current.state !== 'open' || current.head.sha !== run.head_sha) return;
  await github.rest.issues.createComment({
    ...context.repo, issue_number: pr.number,
    body: `### ${title}\n\n${detail}\n\nCommit: \`${run.head_sha}\`\n\n[View build logs and downloadable reports](${runUrl})`,
  });
  if (passed) {
    await github.rest.issues.addLabels({
      ...context.repo, issue_number: pr.number, labels: ['build-passed'],
    });
  } else {
    await removeLabel(github, context.repo, pr.number, 'build-passed');
  }
  await removeLabel(github, context.repo, pr.number, 'ok-to-build');
}

module.exports = { resolvePullRequest, reportBuild };
