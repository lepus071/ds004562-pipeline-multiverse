%% Arm B first-level MVPA GLM (fMRIPrep inputs, original event design).
% Set ARM_B_SUBJECT to a two-digit ID. Defaults to the sub-01 pilot.

clear; clc;
projectRoot = '<DATA_ROOT>';
subject = getenv('ARM_B_SUBJECT');
if isempty(subject); subject = '01'; end
assert(~isempty(regexp(subject, '^\d\d$', 'once')), 'ARM_B_SUBJECT must be two digits.');

manifest = jsondecode(fileread(fullfile(projectRoot, 'docs', 'subject_manifest.json')));
subjects = manifest.D1_full.subjects;
if isnumeric(subjects); subjects = compose('%02d', subjects); end
assert(any(strcmp(subjects, subject)), 'sub-%s is not in frozen D1-full.', subject);
behaviorIndex = str2double(subject); % behavior arrays retain original 01..23 indexing

addpath('<SPM12_ROOT>');
spm('defaults', 'FMRI');
spm_jobman('initcfg');

subjectLabel = ['sub-' subject];
stem = [subjectLabel '_ses-02fmri_task-adaptation'];
inputDir = fullfile(projectRoot, 'derivatives', 'arm-b', 'glm-inputs', subjectLabel, 'func');
outputDir = fullfile(projectRoot, 'derivatives', 'arm-b', 'glm-1stlevel', subjectLabel);
boldFile = fullfile(inputDir, ['s2' stem '_space-T1w_desc-preproc_bold.nii']);
regressorFile = fullfile(inputDir, [stem '_arm-b_regressors.mat']);
eventFile = fullfile(projectRoot, 'ds004562', subjectLabel, 'ses-02fmri', 'func', ...
    [stem '_events.tsv']);
behaviorFile = fullfile(projectRoot, 'ds004562', 'derivatives', 'behavior', 'beh_results.mat');

assert(isfile(boldFile), 'Missing staged BOLD: %s', boldFile);
assert(isfile(regressorFile), 'Missing staged regressors: %s', regressorFile);
assert(isfile(eventFile), 'Missing events: %s', eventFile);
assert(isfile(behaviorFile), 'Missing behavior results: %s', behaviorFile);
if ~exist(outputDir, 'dir'); mkdir(outputDir); end
assert(~isfile(fullfile(outputDir, 'SPM.mat')), ...
    'Refusing to overwrite existing GLM: %s', outputDir);

reg = load(regressorFile, 'move_cov', 'move_derivative_cov', 'R');
beh = load(behaviorFile, 'is_tooExplored_trial');
events = readtable(eventFile, 'FileType', 'text', 'TreatAsMissing', 'n/a');

scans = cellstr(spm_select('expand', boldFile));
nVolumes = numel(scans);
assert(nVolumes == 1360, 'Expected 1360 volumes, found %d.', nVolumes);
assert(size(reg.move_cov,1) == nVolumes && size(reg.move_cov,2) == 6, 'Bad motion dimensions.');
assert(isequal(size(reg.move_derivative_cov), [nVolumes 6]), 'Bad derivative dimensions.');
assert(size(reg.R,1) == nVolumes, 'Bad outlier dimensions.');
assert(all(isfinite(reg.move_cov), 'all'), 'Non-finite motion values.');
assert(all(isfinite(reg.move_derivative_cov), 'all'), 'Non-finite derivative values.');
assert(all(isfinite(reg.R), 'all'), 'Non-finite outlier values.');

directions = {'rightward','upward','leftward','downward'};
clear matlabbatch;
spec = struct();
spec.dir = {outputDir};
spec.timing.units = 'secs';
spec.timing.RT = 2.3;
spec.timing.fmri_t = 16;
spec.timing.fmri_t0 = 8;
spec.sess.scans = scans;

conditionIndex = 0;
for sessionIndex = 1:15
    inSession = events.session_number == sessionIndex;
    onset = events.onset(inSession);
    duration = events.duration(inSession);
    sessionTypeCell = unique(events.session_type(inSession));
    sessionType = sessionTypeCell{1};
    stimulusDirection = events.stimulus_direction(inSession);
    tooExplored = squeeze(beh.is_tooExplored_trial(behaviorIndex, 2, sessionIndex, :));

    conditionIndex = conditionIndex + 1;
    spec.sess.cond(conditionIndex) = make_condition(['session_start_' sessionType], onset(1), duration(1));
    conditionIndex = conditionIndex + 1;
    spec.sess.cond(conditionIndex) = make_condition('first trial (excluded)', onset(2), duration(2));

    erasingOnset = onset(3:18);
    erasingDuration = duration(3:18);
    erasingDirection = stimulusDirection(3:18);
    tooExplored(1) = [];
    assert(numel(tooExplored) == 16, 'Unexpected too-explored vector length.');

    for directionIndex = 1:4
        selected = strcmp(erasingDirection, directions{directionIndex});
        selected(tooExplored) = false;
        assert(any(selected), 'No valid %s trial in session %d.', directions{directionIndex}, sessionIndex);
        conditionIndex = conditionIndex + 1;
        spec.sess.cond(conditionIndex) = make_condition( ...
            ['erasing_' sessionType '_' directions{directionIndex}], ...
            erasingOnset(selected), erasingDuration(selected));
    end

    % Preserve the published code's naming bug: all too-explored regressors
    % receive the final direction label. Their timing and design are unchanged.
    for tooIndex = find(tooExplored)'
        conditionIndex = conditionIndex + 1;
        spec.sess.cond(conditionIndex) = make_condition( ...
            ['erasing_too_explored_' sessionType '_' directions{directionIndex}], ...
            erasingOnset(tooIndex), erasingDuration(tooIndex));
    end

    conditionIndex = conditionIndex + 1;
    spec.sess.cond(conditionIndex) = make_condition('score', onset(19), duration(19));
    conditionIndex = conditionIndex + 1;
    spec.sess.cond(conditionIndex) = make_condition('session end', onset(20), duration(20));
end

spec.sess.multi = {''};
regressorIndex = 0;
for motionIndex = 1:6
    regressorIndex = regressorIndex + 1;
    spec.sess.regress(regressorIndex).name = sprintf('Move %02d', motionIndex);
    spec.sess.regress(regressorIndex).val = reg.move_cov(:,motionIndex);
    regressorIndex = regressorIndex + 1;
    spec.sess.regress(regressorIndex).name = sprintf('Move %02d (fMRIPrep derivative1)', motionIndex);
    spec.sess.regress(regressorIndex).val = reg.move_derivative_cov(:,motionIndex);
end
for outlierIndex = 1:size(reg.R,2)
    regressorIndex = regressorIndex + 1;
    spec.sess.regress(regressorIndex).name = sprintf('Outlier %02d', outlierIndex);
    spec.sess.regress(regressorIndex).val = reg.R(:,outlierIndex);
end
spec.sess.multi_reg = {''};
spec.sess.hpf = 128;
spec.fact = struct('name', {}, 'levels', {});
spec.bases.hrf.derivs = [0 0];
spec.volt = 1;
spec.global = 'None';
spec.mthresh = 0.8;
spec.mask = {''};
spec.cvi = 'AR(1)';

matlabbatch{1}.spm.stats.fmri_spec = spec;
matlabbatch{2}.spm.stats.fmri_est.spmmat(1) = cfg_dep( ...
    'fMRI model specification: SPM.mat File', ...
    substruct('.','val','{}',{1},'.','val','{}',{1},'.','val','{}',{1}), ...
    substruct('.','spmmat'));
matlabbatch{2}.spm.stats.fmri_est.write_residuals = 0;
matlabbatch{2}.spm.stats.fmri_est.method.Classical = 1;

fprintf('Arm B GLM %s: %d conditions, %d nuisance regressors (%d outliers)\n', ...
    subjectLabel, conditionIndex, regressorIndex, size(reg.R,2));
spm_jobman('run', matlabbatch);
fprintf('Arm B GLM complete: %s\n', subjectLabel);

function condition = make_condition(name, onset, duration)
condition.name = name;
condition.onset = onset;
condition.duration = duration;
condition.tmod = 0;
condition.pmod = struct('name', {}, 'param', {}, 'poly', {});
condition.orth = 1;
end
