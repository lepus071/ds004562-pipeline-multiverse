function prepare_arm_a_tfce_reconstruction
% Prepare FSL randomise inputs for the Arm A reconstruction of Song et al. Figures 6-10.

rootDir = '<DATA_ROOT>';
mvpaDir = fullfile(rootDir, 'ds004562', 'derivatives', 'spm-mvpa');
outputDir = fullfile(mvpaDir, 'TFCE_reconstruction');
if ~isfolder(outputDir), mkdir(outputDir); end

analyses = struct( ...
    'label', { ...
        'figure6_visual_direction', ...
        'figure7_movement_direction', ...
        'figure8_task_context_posneg90', ...
        'figure9_prepare_posneg90', ...
        'figure9_prepare_rotation_vs_mirror', ...
        'figure10a_rotation_performance_negative', ...
        'figure10b_mirror_performance_negative'}, ...
    'groupDir', { ...
        'GroupLevel_MVPA_VisualDirection_Alltask', ...
        'GroupLevel_MVPA_MoveDirection_Alltasks', ...
        'GroupLevel_MVPA_TaskContext_CV_posneg90s_mask-ICV_replacement', ...
        'GroupLevel_MVPA_PreparePeriod_posneg90s', ...
        'GroupLevel_MVPA_PreparePeriod_rotationVSmirror', ...
        'GroupLevel_MVPA_TaskContext_posneg90s_regression', ...
        'GroupLevel_MVPA_TaskContext_rotationVSmirror_regression_withConfounds'}, ...
    'contrast', {1, 1, 1, 1, 1, [0 -1], [0 -1 0]}, ...
    'contrastName', { ...
        'positive_group_mean', 'positive_group_mean', 'positive_group_mean', ...
        'positive_group_mean', 'positive_group_mean', ...
        'negative_rotation_performance_slope', 'negative_mirror_performance_slope'});

expectedSubjects = cellstr(compose('sub-%02d', [1:15 17:23]));
configRows = cell(numel(analyses), 3);

for analysisIdx = 1:numel(analyses)
    analysis = analyses(analysisIdx);
    groupDir = fullfile(mvpaDir, analysis.groupDir);
    spmFile = fullfile(groupDir, 'SPM.mat');
    assert(isfile(spmFile), 'Missing group model: %s', spmFile);
    loaded = load(spmFile, 'SPM');
    SPM = loaded.SPM;

    scans = cellstr(SPM.xY.P);
    assert(numel(scans) == 22, '%s has %d scans, expected 22.', analysis.label, numel(scans));
    assert(all(cellfun(@isfile, scans)), 'One or more scans are missing for %s.', analysis.label);
    observedSubjects = cellfun(@subjectFromPath, scans, 'UniformOutput', false);
    assert(isequal(observedSubjects(:), expectedSubjects(:)), ...
        'Subject order mismatch for %s.', analysis.label);

    design = SPM.xX.X;
    contrast = analysis.contrast;
    assert(size(design, 1) == numel(scans), 'Design row mismatch for %s.', analysis.label);
    assert(size(design, 2) == numel(contrast), 'Contrast width mismatch for %s.', analysis.label);
    assert(rank(design) == size(design, 2), 'Rank-deficient design for %s.', analysis.label);

    analysisDir = fullfile(outputDir, analysis.label);
    if ~isfolder(analysisDir), mkdir(analysisDir); end
    writeLines(fullfile(analysisDir, 'scans.txt'), scans);
    writeLines(fullfile(analysisDir, 'subjects.txt'), expectedSubjects);
    writeVestMatrix(fullfile(analysisDir, 'design.mat'), design);
    writeVestContrast(fullfile(analysisDir, 'design.con'), contrast, analysis.contrastName);

    sourceMask = fullfile(groupDir, SPM.VM.fname);
    assert(isfile(sourceMask), 'Missing SPM model mask: %s', sourceMask);
    configRows(analysisIdx, :) = {analysis.label, sourceMask, analysis.groupDir};

    metadata = struct();
    metadata.analysis = analysis.label;
    metadata.source_group_model = spmFile;
    metadata.source_mask = sourceMask;
    metadata.source_scans = scans;
    metadata.subjects = expectedSubjects;
    metadata.design_column_names = SPM.xX.name;
    metadata.design_matrix = design;
    metadata.contrast_name = analysis.contrastName;
    metadata.contrast = contrast;
    writeJson(fullfile(analysisDir, 'input_provenance.json'), metadata);
end

configFile = fullfile(outputDir, 'analyses.tsv');
fid = fopen(configFile, 'w');
assert(fid ~= -1, 'Could not write %s.', configFile);
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, 'label\tsource_mask\tsource_group_model\n');
for rowIdx = 1:size(configRows, 1)
    fprintf(fid, '%s\t%s\t%s\n', configRows{rowIdx, 1}, configRows{rowIdx, 2}, configRows{rowIdx, 3});
end
clear cleaner;

runMetadata = struct();
runMetadata.status = 'prepared';
runMetadata.created_at = char(datetime('now', 'TimeZone', 'Asia/Taipei', ...
    'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
runMetadata.paper = 'Song et al. (2023), Frontiers in Human Neuroscience 17:1221944';
runMetadata.scope = 'Reconstructed corrected significance maps for Figures 6-10';
runMetadata.n_participants = 22;
runMetadata.participants = expectedSubjects;
runMetadata.permutations = 5000;
runMetadata.one_sided = true;
runMetadata.random_seed = 20260903;
runMetadata.tfce_H = 2;
runMetadata.tfce_E = 0.5;
runMetadata.tfce_connectivity = 6;
runMetadata.fwe_alpha = 0.05;
runMetadata.figure9_fdr_q = 0.05;
runMetadata.figure8_mask_substitution = ['SPM mask_ICV.nii via the documented ' ...
    'GroupLevel_MVPA_TaskContext_CV_posneg90s_mask-ICV_replacement model'];
runMetadata.software = 'FSL randomise; version captured by run script';
runMetadata.warning = ['Reconstruction under explicit assumptions; not a claim of exact ' ...
    'voxelwise reproduction of the unpublished author inference.'];
writeJson(fullfile(outputDir, 'run_provenance.json'), runMetadata);

fprintf('Prepared %d TFCE analyses in %s\n', numel(analyses), outputDir);
end

function subject = subjectFromPath(pathValue)
match = regexp(pathValue, 'sub-\d{2}', 'match', 'once');
assert(~isempty(match), 'No subject ID found in %s.', pathValue);
subject = match;
end

function writeLines(filename, values)
fid = fopen(filename, 'w');
assert(fid ~= -1, 'Could not write %s.', filename);
cleaner = onCleanup(@() fclose(fid));
for valueIdx = 1:numel(values)
    fprintf(fid, '%s\n', values{valueIdx});
end
end

function writeVestMatrix(filename, matrix)
fid = fopen(filename, 'w');
assert(fid ~= -1, 'Could not write %s.', filename);
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '/NumWaves\t%d\n', size(matrix, 2));
fprintf(fid, '/NumPoints\t%d\n', size(matrix, 1));
fprintf(fid, '/PPheights');
ppHeights = max(abs(matrix), [], 1);
ppHeights(ppHeights == 0) = 1;
fprintf(fid, '\t%.10g', ppHeights);
fprintf(fid, '\n/Matrix\n');
for rowIdx = 1:size(matrix, 1)
    fprintf(fid, '%.12g', matrix(rowIdx, 1));
    fprintf(fid, '\t%.12g', matrix(rowIdx, 2:end));
    fprintf(fid, '\n');
end
end

function writeVestContrast(filename, contrast, contrastName)
fid = fopen(filename, 'w');
assert(fid ~= -1, 'Could not write %s.', filename);
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '/ContrastName1\t%s\n', contrastName);
fprintf(fid, '/NumWaves\t%d\n', numel(contrast));
fprintf(fid, '/NumContrasts\t1\n');
fprintf(fid, '/PPheights\t1\n');
fprintf(fid, '/RequiredEffect\t1\n');
fprintf(fid, '/Matrix\n');
fprintf(fid, '%.12g', contrast(1));
fprintf(fid, '\t%.12g', contrast(2:end));
fprintf(fid, '\n');
end

function writeJson(filename, value)
fid = fopen(filename, 'w');
assert(fid ~= -1, 'Could not write %s.', filename);
cleaner = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(value, PrettyPrint=true));
end
