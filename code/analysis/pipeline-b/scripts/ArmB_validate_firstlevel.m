%% Validate every frozen Arm B first-level GLM and write a machine-readable report.
clear; clc;
root = '<DATA_ROOT>';
addpath('<SPM12_ROOT>');
manifest = jsondecode(fileread(fullfile(root, 'docs', 'subject_manifest.json')));
subjects = manifest.D1_full.subjects;
if isnumeric(subjects); subjects = compose('%02d', subjects); end

rows = cell(numel(subjects), 10);
for i = 1:numel(subjects)
    subject = char(subjects{i});
    d = fullfile(root, 'derivatives', 'arm-b', 'glm-1stlevel', ['sub-' subject]);
    q = load(fullfile(d, 'SPM.mat'), 'SPM'); S = q.SPM;
    names = S.xX.name;
    main = sum(~cellfun('isempty', regexp(names, 'Sn\(1\) erasing_(rotation|mirror)', 'once')) & ...
        cellfun('isempty', regexp(names, 'too_explored', 'once')));
    nuisance = sum(contains(names, 'Move ') | contains(names, 'Outlier '));
    outliers = sum(contains(names, 'Outlier '));
    mask = spm_read_vols(spm_vol(fullfile(d, 'mask.nii'))) > 0;
    betas = dir(fullfile(d, 'beta_*.nii'));
    nonfiniteBetas = 0;
    for k = 1:numel(betas)
        values = spm_read_vols(spm_vol(fullfile(d, betas(k).name)));
        nonfiniteBetas = nonfiniteBetas + any(~isfinite(values(mask)));
    end
    scans = sum(S.nscan);
    columns = size(S.xX.X, 2);
    designRank = rank(S.xX.X);
    passed = scans == 1360 && main == 60 && nuisance == 12 + outliers && ...
        columns == numel(betas) && designRank == columns && nnz(mask) > 0 && nonfiniteBetas == 0;
    assert(passed, 'Validation failed for sub-%s.', subject);
    rows(i,:) = {['sub-' subject], scans, columns, designRank, main, nuisance, ...
        outliers, numel(betas), nnz(mask), nonfiniteBetas};
    fprintf('validated sub-%s (%d betas, %d outliers)\n', subject, numel(betas), outliers);
end

report = cell2table(rows, 'VariableNames', {'subject','scans','design_columns','design_rank', ...
    'main_erasing','nuisance','outliers','betas','mask_voxels','nonfinite_betas'});
writetable(report, fullfile(root, 'logs', 'arm_b_firstlevel_validation.tsv'), ...
    'FileType', 'text', 'Delimiter', '\t');
fprintf('Arm B first-level validation complete: %d/%d passed\n', height(report), numel(subjects));
