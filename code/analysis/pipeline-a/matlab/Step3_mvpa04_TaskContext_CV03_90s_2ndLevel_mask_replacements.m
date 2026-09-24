%% Re-run the missing-GMmask group model with documented replacement masks.
% This script intentionally leaves GroupLevel_MVPA_TaskContext_CV_posneg90s
% untouched as the provenance record of the failed original analysis.
clear; clc;

spm('defaults','FMRI');
spm_jobman('initcfg');

currentPath = pwd;
cleanupObj = onCleanup(@() cd(currentPath));
cd ../temp
load('tempFileForAnalysis.mat', 'pathBIDS', 'pathSPM');

pathDeriv = fullfile(pathBIDS, 'derivatives');
pathSPMmvpa = fullfile(pathDeriv, 'spm-mvpa');
pathMVPA = fullfile(pathSPMmvpa, 'MVPA_TaskContext_CV_posneg90s');
pathBehavior = fullfile(pathDeriv, 'behavior', 'beh_results.mat');
load(pathBehavior, 'outlier_idx');

mvpaSubjects = dir(fullfile(pathMVPA, 'sub-*'));
mvpaSubjects = mvpaSubjects([mvpaSubjects.isdir]);
[~, order] = sort({mvpaSubjects.name});
mvpaSubjects = mvpaSubjects(order);

resFileList = cell(numel(mvpaSubjects), 1);
for nsub = 1:numel(mvpaSubjects)
    resFileList{nsub} = fullfile(mvpaSubjects(nsub).folder, ...
        mvpaSubjects(nsub).name, 's8wres_accuracy_minus_chance.nii');
    assert(isfile(resFileList{nsub}), 'Missing input: %s', resFileList{nsub});
end
assert(numel(resFileList) == 23, 'Expected 23 subject maps before sub-16 exclusion.');
assert(strcmp(mvpaSubjects(outlier_idx).name, 'sub-16'), ...
    'outlier_idx no longer points to sub-16; refusing to continue.');
resFileList(outlier_idx) = [];
assert(numel(resFileList) == 22, 'Expected 22 maps after sub-16 exclusion.');

% Sensitivity mask: SPM12 gray-matter tissue prior thresholded at P(GM)>=0.20.
replacementMaskDir = fullfile(pathSPMmvpa, 'replacement_masks');
if ~isfolder(replacementMaskDir), mkdir(replacementMaskDir); end
gmMask = fullfile(replacementMaskDir, 'SPM12_TPM_GM_p20.nii');
if ~isfile(gmMask)
    clear matlabbatch
    matlabbatch{1}.spm.util.imcalc.input = {fullfile(pathSPM, 'tpm', 'TPM.nii,1')};
    matlabbatch{1}.spm.util.imcalc.output = 'SPM12_TPM_GM_p20.nii';
    matlabbatch{1}.spm.util.imcalc.outdir = {replacementMaskDir};
    matlabbatch{1}.spm.util.imcalc.expression = 'i1>=0.20';
    matlabbatch{1}.spm.util.imcalc.var = struct('name', {}, 'value', {});
    matlabbatch{1}.spm.util.imcalc.options.dmtx = 0;
    matlabbatch{1}.spm.util.imcalc.options.mask = 0;
    matlabbatch{1}.spm.util.imcalc.options.interp = 1;
    matlabbatch{1}.spm.util.imcalc.options.dtype = 2;
    spm_jobman('run', matlabbatch);
end
assert(isfile(gmMask), 'Failed to create sensitivity mask: %s', gmMask);

variants = struct( ...
    'label', {'mask-ICV_replacement', 'mask-SPMGMp20_sensitivity'}, ...
    'mask', {fullfile(pathSPM, 'tpm', 'mask_ICV.nii'), gmMask}, ...
    'description', { ...
        'Primary replacement: unmodified SPM12 TPM mask_ICV.nii, matching the other shared MVPA group scripts.', ...
        'Sensitivity replacement: SPM12 TPM.nii gray-matter prior (volume 1), thresholded P(GM)>=0.20 and binarized.'});

for variantIdx = 1:numel(variants)
    targetName = ['GroupLevel_MVPA_TaskContext_CV_posneg90s_' variants(variantIdx).label];
    targetPath = fullfile(pathSPMmvpa, targetName);
    if isfile(fullfile(targetPath, 'SPM.mat'))
        error('Output already contains SPM.mat; refusing to overwrite: %s', targetPath);
    end
    if ~isfolder(targetPath), mkdir(targetPath); end

    clear matlabbatch
    matlabbatch{1}.spm.stats.factorial_design.dir = {targetPath};
    matlabbatch{1}.spm.stats.factorial_design.des.t1.scans = resFileList;
    matlabbatch{1}.spm.stats.factorial_design.cov = struct('c', {}, 'cname', {}, 'iCFI', {}, 'iCC', {});
    matlabbatch{1}.spm.stats.factorial_design.multi_cov = struct('files', {}, 'iCFI', {}, 'iCC', {});
    matlabbatch{1}.spm.stats.factorial_design.masking.tm.tm_none = 1;
    matlabbatch{1}.spm.stats.factorial_design.masking.im = 1;
    matlabbatch{1}.spm.stats.factorial_design.masking.em = {[variants(variantIdx).mask ',1']};
    matlabbatch{1}.spm.stats.factorial_design.globalc.g_omit = 1;
    matlabbatch{1}.spm.stats.factorial_design.globalm.gmsca.gmsca_no = 1;
    matlabbatch{1}.spm.stats.factorial_design.globalm.glonorm = 1;

    matlabbatch{2}.spm.stats.fmri_est.spmmat(1) = cfg_dep( ...
        'Factorial design specification: SPM.mat File', ...
        substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), ...
        substruct('.','spmmat'));
    matlabbatch{2}.spm.stats.fmri_est.write_residuals = 0;
    matlabbatch{2}.spm.stats.fmri_est.method.Classical = 1;

    matlabbatch{3}.spm.stats.con.spmmat(1) = cfg_dep( ...
        'Model estimation: SPM.mat File', ...
        substruct('.','val', '{}',{2}, '.','val', '{}',{1}, '.','val', '{}',{1}), ...
        substruct('.','spmmat'));
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.name = 'result';
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.weights = 1;
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.delete = 0;

    fprintf('Running %s with mask %s\n', variants(variantIdx).label, variants(variantIdx).mask);
    spm_jobman('run', matlabbatch);

    provenance = struct();
    provenance.analysis = 'Step3_mvpa04 TaskContext CV +90 versus -90 group one-sample t-test';
    provenance.variant = variants(variantIdx).label;
    provenance.description = variants(variantIdx).description;
    provenance.explicit_mask = variants(variantIdx).mask;
    provenance.subject_count = numel(resFileList);
    provenance.excluded_subject = 'sub-16';
    provenance.original_failure_directory = fullfile(pathSPMmvpa, 'GroupLevel_MVPA_TaskContext_CV_posneg90s');
    provenance.generated_utc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ssXXX'));
    provenanceFile = fullfile(targetPath, 'mask_replacement_provenance.json');
    fid = fopen(provenanceFile, 'w');
    assert(fid ~= -1, 'Could not write provenance: %s', provenanceFile);
    fprintf(fid, '%s\n', jsonencode(provenance, PrettyPrint=true));
    fclose(fid);
end

disp('Completed both documented GMmask replacement analyses.');
