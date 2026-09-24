%% Stage fMRIPrep outputs for the Arm B first-level GLM.
% Idempotent: completed subjects are validated and skipped. This script does
% not modify Arm A or the original Song et al. analysis tree.

clear; clc;

projectRoot = '<DATA_ROOT>';
fmriprepRoot = fullfile(projectRoot, 'derivatives', 'fmriprep-ds004562');
armBRoot = fullfile(projectRoot, 'derivatives', 'arm-b');
manifestPath = fullfile(projectRoot, 'docs', 'subject_manifest.json');

addpath('<SPM12_ROOT>');
spm('defaults', 'FMRI');
spm_jobman('initcfg');

manifest = jsondecode(fileread(manifestPath));
subjects = manifest.D1_full.subjects;
if isnumeric(subjects)
    subjects = compose('%02d', subjects);
end
assert(numel(subjects) == manifest.D1_full.n, 'Manifest count mismatch.');
assert(~any(strcmp(subjects, '16')), 'Frozen D1-full list must exclude sub-16.');

motionNames = {'trans_x','trans_y','trans_z','rot_x','rot_y','rot_z'};
derivativeNames = strcat(motionNames, '_derivative1');

for subjectIndex = 1:numel(subjects)
    subject = char(subjects{subjectIndex});
    subjectLabel = ['sub-' subject];
    inputFunc = fullfile(fmriprepRoot, subjectLabel, 'ses-02fmri', 'func');
    outputFunc = fullfile(armBRoot, 'glm-inputs', subjectLabel, 'func');
    if ~exist(outputFunc, 'dir'); mkdir(outputFunc); end

    stem = [subjectLabel '_ses-02fmri_task-adaptation'];
    sourceGz = fullfile(inputFunc, [stem '_space-T1w_desc-preproc_bold.nii.gz']);
    confoundsTsv = fullfile(inputFunc, [stem '_desc-confounds_timeseries.tsv']);
    sourceNii = fullfile(outputFunc, [stem '_space-T1w_desc-preproc_bold.nii']);
    smoothNii = fullfile(outputFunc, ['s2' stem '_space-T1w_desc-preproc_bold.nii']);
    regressorsMat = fullfile(outputFunc, [stem '_arm-b_regressors.mat']);
    outliersMat = fullfile(outputFunc, ['art_regression_outliers_' stem '_bold.mat']);

    assert(isfile(sourceGz), 'Missing BOLD: %s', sourceGz);
    assert(isfile(confoundsTsv), 'Missing confounds: %s', confoundsTsv);

    if ~isfile(sourceNii)
        fprintf('[%s] decompressing BOLD\n', subjectLabel);
        gunzip(sourceGz, outputFunc);
    end

    if ~isfile(smoothNii)
        fprintf('[%s] applying 2 mm FWHM smoothing\n', subjectLabel);
        clear matlabbatch;
        expanded = cellstr(spm_select('expand', sourceNii));
        matlabbatch{1}.spm.spatial.smooth.data = expanded;
        matlabbatch{1}.spm.spatial.smooth.fwhm = [2 2 2];
        matlabbatch{1}.spm.spatial.smooth.dtype = 0;
        matlabbatch{1}.spm.spatial.smooth.im = 0;
        matlabbatch{1}.spm.spatial.smooth.prefix = 's2';
        spm_jobman('run', matlabbatch);
    end

    fprintf('[%s] extracting named confounds\n', subjectLabel);
    confounds = readtable(confoundsTsv, 'FileType', 'text', ...
        'VariableNamingRule', 'preserve', 'TreatAsMissing', 'n/a');
    nVolumes = size(confounds, 1);
    move_cov = zeros(nVolumes, 6);
    move_derivative_cov = zeros(nVolumes, 6);
    for columnIndex = 1:6
        assert(ismember(motionNames{columnIndex}, confounds.Properties.VariableNames), ...
            'Missing confound %s for %s', motionNames{columnIndex}, subjectLabel);
        assert(ismember(derivativeNames{columnIndex}, confounds.Properties.VariableNames), ...
            'Missing confound %s for %s', derivativeNames{columnIndex}, subjectLabel);
        move_cov(:, columnIndex) = confounds.(motionNames{columnIndex});
        move_derivative_cov(:, columnIndex) = confounds.(derivativeNames{columnIndex});
    end
    move_derivative_cov(isnan(move_derivative_cov)) = 0;
    assert(all(isfinite(move_cov), 'all'), 'Non-finite base motion value for %s', subjectLabel);
    assert(all(isfinite(move_derivative_cov), 'all'), 'Non-finite derivative for %s', subjectLabel);

    outlierMask = startsWith(confounds.Properties.VariableNames, 'motion_outlier');
    outlierNames = confounds.Properties.VariableNames(outlierMask);
    R = confounds{:, outlierMask}; %#ok<NASGU>
    if isempty(R); R = zeros(nVolumes, 0); end %#ok<NASGU>
    assert(all(isfinite(R), 'all'), 'Non-finite motion outlier for %s', subjectLabel);

    save(regressorsMat, 'move_cov', 'move_derivative_cov', 'R', ...
        'motionNames', 'derivativeNames', 'outlierNames', 'confoundsTsv', ...
        'manifestPath', 'subject', '-v7.3');
    save(outliersMat, 'R');
    writematrix(move_cov, fullfile(outputFunc, ['rp_' stem '.txt']), 'Delimiter', 'tab');

    info = niftiinfo(smoothNii);
    assert(info.ImageSize(4) == nVolumes, 'BOLD/confounds row mismatch for %s', subjectLabel);
    fprintf('[%s] complete: %d volumes, %d outliers\n', ...
        subjectLabel, nVolumes, size(R, 2));
end

fprintf('Arm B staging complete for %d frozen D1-full subjects.\n', numel(subjects));
