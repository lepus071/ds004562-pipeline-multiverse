%% SPM half of paired-mask construction. Environment: MASK_SUBJECT, MASK_MODE.
clear; clc;
root = '<DATA_ROOT>';
subject = getenv('MASK_SUBJECT');
mode = getenv('MASK_MODE');
assert(~isempty(regexp(subject, '^\d\d$', 'once')), 'MASK_SUBJECT must be two digits.');
assert(any(strcmp(mode, {'to_canonical','to_native'})), 'Invalid MASK_MODE.');

addpath('<SPM12_ROOT>');
spm('defaults', 'FMRI');
spm_jobman('initcfg');

label = ['sub-' subject];
outdir = fullfile(root, 'derivatives', 'common-searchlight-masks', label);
if ~exist(outdir, 'dir'); mkdir(outdir); end
yfile = fullfile(root, 'ds004562', 'derivatives', 'spm-preproc', label, 'anat', ...
    ['y_' label '_ses-02fmri_T1w.nii']);
nativeMask = fullfile(root, 'ds004562', 'derivatives', 'spm-mvpa', ...
    'glm-1stlevel', label, 'mask.nii');
canonicalRef = fullfile(root, 'derivatives', 'common-searchlight-masks', ...
    'tpl-MNI152NLin6Asym_res-02_desc-brain_mask.nii');
assert(isfile(yfile) && isfile(nativeMask) && isfile(canonicalRef), 'Required input missing.');

clear matlabbatch;
if strcmp(mode, 'to_canonical')
    % SPM y_* is defined on its MNI grid and points into native source
    % coordinates, so it directly pulls the native GLM mask into MNI.
    matlabbatch{1}.spm.util.defs.comp{1}.def = {yfile};
    source = nativeMask;
    prefix = 'arm-a_to_canonical_';
    destination = fullfile(outdir, 'arm-a_canonical_spm15_coverage.nii');
else
    % Invert the deformation on the native EPI reference grid to pull the
    % paired canonical support back into native EPI space.
    matlabbatch{1}.spm.util.defs.comp{1}.inv.comp{1}.def = {yfile};
    matlabbatch{1}.spm.util.defs.comp{1}.inv.space = {nativeMask};
    source = fullfile(outdir, 'canonical_common_mask.nii');
    assert(isfile(source), 'Canonical common mask missing: %s', source);
    prefix = 'canonical_to_arm-a_';
    destination = fullfile(outdir, 'arm-a_explicit_mask_unclipped.nii');
end
matlabbatch{1}.spm.util.defs.out{1}.pull.fnames = {source};
matlabbatch{1}.spm.util.defs.out{1}.pull.savedir.saveusr = {outdir};
matlabbatch{1}.spm.util.defs.out{1}.pull.interp = 0;
matlabbatch{1}.spm.util.defs.out{1}.pull.mask = 1;
matlabbatch{1}.spm.util.defs.out{1}.pull.fwhm = [0 0 0];
matlabbatch{1}.spm.util.defs.out{1}.pull.prefix = prefix;
spm_jobman('run', matlabbatch);

[~, base, ext] = fileparts(source);
produced = fullfile(outdir, [prefix base ext]);
assert(isfile(produced), 'SPM did not create expected output: %s', produced);
if isfile(destination); delete(destination); end
movefile(produced, destination);
fprintf('%s %s complete: %s\n', label, mode, destination);
