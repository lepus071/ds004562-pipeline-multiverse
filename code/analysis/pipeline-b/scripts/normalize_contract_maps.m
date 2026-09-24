%% Normalize contract decoding maps to the frozen SPM grid, then smooth 8 mm.
% NORMALIZE_SUBJECTS: "01" for pilot or "all" (default) for frozen cohort.
clear; clc;
root = '<DATA_ROOT>';
selection = getenv('NORMALIZE_SUBJECTS');
if isempty(selection); selection = 'all'; end
manifest = jsondecode(fileread(fullfile(root, 'docs', 'subject_manifest.json')));
subjects = manifest.D1_full.subjects;
if isnumeric(subjects); subjects = compose('%02d', subjects); end
if ~strcmp(selection, 'all')
    assert(any(strcmp(subjects, selection)), 'Subject not in frozen manifest.');
    subjects = {selection};
end
branches = {
    'MVPA_VisualDirection_Alltask'
    'MVPA_MoveDirection_Alltasks'
    'MVPA_TaskContext_CV_posneg90s'
    'MVPA_TaskContext_CV_rotationVSmirror'
    'MVPA_PreparePeriod_posneg90s'
    'MVPA_PreparePeriod_rotationVSmirror'
    'MVPA_TaskContext_posneg90s'
    'MVPA_TaskContext_rotationVSmirror'
    'MVPA_FourDirection_rot_pos90'
    'MVPA_FourDirection_rot_neg90'
    'MVPA_FourDirection_mirror'};

addpath('<SPM12_ROOT>');
spm('defaults','FMRI'); spm_jobman('initcfg');
outroot = fullfile(root, 'derivatives', 'contract-normalized');
reference = fullfile(outroot, 'reference_spm_grid.nii');
assert(isfile(reference), 'Missing frozen reference grid: %s', reference);
ref = spm_vol(reference);
toMNI6 = fullfile(root, '.templateflow', 'tpl-MNI152NLin6Asym', ...
    'tpl-MNI152NLin6Asym_from-MNI152NLin2009cAsym_mode-image_xfm.h5');
ants = '<ANTS_ROOT>/bin/antsApplyTransforms';
assert(isfile(toMNI6) && isfile(ants), 'Missing ANTs/template transform.');

rows = cell(2*numel(subjects)*numel(branches), 11); row = 0;
for subjectIndex = 1:numel(subjects)
    subject = char(subjects{subjectIndex}); label = ['sub-' subject];
    yfile = fullfile(root, 'ds004562', 'derivatives', 'spm-preproc', label, ...
        'anat', ['y_' label '_ses-02fmri_T1w.nii']);
    bforward = fullfile(root, 'derivatives', 'fmriprep-ds004562', label, ...
        'ses-02fmri', 'anat', [label '_ses-02fmri_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5']);
    assert(isfile(yfile) && isfile(bforward), 'Missing transform for %s.', label);
    for branchIndex = 1:numel(branches)
        branch = branches{branchIndex};
        inputA = fullfile(root, 'contract_runs', 'cohort-arm-a', 'bids', ...
            'derivatives', 'spm-mvpa', branch, label, 'res_accuracy_minus_chance.nii');
        inputB = fullfile(root, 'contract_runs', 'cohort-arm-b', 'bids', ...
            'derivatives', 'spm-mvpa', branch, label, 'res_accuracy_minus_chance.nii');
        assert(isfile(inputA) && isfile(inputB), 'Missing decoding input: %s %s', branch, label);

        outA = fullfile(outroot, 'arm-a', branch, label);
        outB = fullfile(outroot, 'arm-b', branch, label);
        if ~exist(outA,'dir'); mkdir(outA); end
        if ~exist(outB,'dir'); mkdir(outB); end
        stagedA = fullfile(outA, 'res_accuracy_minus_chance.nii');
        stagedB = fullfile(outB, 'res_accuracy_minus_chance.nii');
        normA = fullfile(outA, 'wres_accuracy_minus_chance.nii');
        normB = fullfile(outB, 'wres_accuracy_minus_chance.nii');
        smoothA = fullfile(outA, 's8wres_accuracy_minus_chance.nii');
        smoothB = fullfile(outB, 's8wres_accuracy_minus_chance.nii');

        stage_finite(inputA,stagedA);
        stage_finite(inputB,stagedB);
        if isfile(normA) && ~volume_is_finite(normA)
            delete(normA); if isfile(smoothA); delete(smoothA); end
        end
        if isfile(normB) && ~volume_is_finite(normB)
            delete(normB); if isfile(smoothB); delete(smoothB); end
        end
        if ~isfile(normA)
            clear matlabbatch;
            matlabbatch{1}.spm.spatial.normalise.write.subj.def = {yfile};
            matlabbatch{1}.spm.spatial.normalise.write.subj.resample = {stagedA};
            matlabbatch{1}.spm.spatial.normalise.write.woptions.bb = [-78 -112 -70; 78 76 85];
            matlabbatch{1}.spm.spatial.normalise.write.woptions.vox = [2 2 2];
            matlabbatch{1}.spm.spatial.normalise.write.woptions.interp = 4;
            matlabbatch{1}.spm.spatial.normalise.write.woptions.prefix = 'w';
            spm_jobman('run',matlabbatch);
        end
        if ~isfile(normB)
            cmd = sprintf('env LD_LIBRARY_PATH= "%s" -d 3 -i "%s" -r "%s" -o "%s" -n "BSpline[4]" -t "%s" -t "%s"', ...
                ants,stagedB,reference,normB,toMNI6,bforward);
            [code,message] = system(cmd);
            assert(code==0, 'ANTs failed for %s %s: %s',branch,label,message);
        end
        changedA=sanitize_in_place(normA);
        changedB=sanitize_in_place(normB);
        if changedA && isfile(smoothA); delete(smoothA); end
        if changedB && isfile(smoothB); delete(smoothB); end
        if ~isfile(smoothA) || ~isfile(smoothB)
            clear matlabbatch;
            matlabbatch{1}.spm.spatial.smooth.data = {normA;normB};
            matlabbatch{1}.spm.spatial.smooth.fwhm = [8 8 8];
            matlabbatch{1}.spm.spatial.smooth.dtype = 0;
            matlabbatch{1}.spm.spatial.smooth.im = 0;
            matlabbatch{1}.spm.spatial.smooth.prefix = 's8';
            spm_jobman('run',matlabbatch);
        end

        for armIndex = 1:2
            arm = sprintf('arm-%c','a'+armIndex-1);
            if armIndex==1; nfile=normA; sfile=smoothA; else; nfile=normB; sfile=smoothB; end
            nv=spm_vol(nfile); sv=spm_vol(sfile);
            exactDim=isequal(nv.dim,ref.dim) && isequal(sv.dim,ref.dim);
            affineDelta=max(abs(nv.mat-ref.mat),[],'all');
            smoothAffineDelta=max(abs(sv.mat-ref.mat),[],'all');
            ndata=spm_read_vols(nv); sdata=spm_read_vols(sv);
            finite=all(isfinite(ndata),'all') && all(isfinite(sdata),'all');
            assert(exactDim && affineDelta<1e-5 && smoothAffineDelta<1e-5 && finite, ...
                'Grid/QC failure: %s %s %s',arm,branch,label);
            row=row+1;
            rows(row,:)={arm,branch,label,nv.dim(1),nv.dim(2),nv.dim(3), ...
                affineDelta,smoothAffineDelta,min(ndata,[],'all'),max(ndata,[],'all'),finite};
        end
    end
    fprintf('normalized and smoothed %s: %d branches x 2 arms\n',label,numel(branches));
end
report=cell2table(rows,'VariableNames',{'arm','branch','subject','dim_x','dim_y','dim_z', ...
    'normalized_affine_max_delta','smoothed_affine_max_delta','normalized_min','normalized_max','finite'});
if strcmp(selection,'all'); reportName='contract_normalization_validation.tsv';
else; reportName=['contract_normalization_pilot_' selection '.tsv']; end
writetable(report,fullfile(root,'logs',reportName),'FileType','text','Delimiter','\t');
fprintf('Normalization validation complete: %d maps x normalized/smoothed.\n',height(report));

function stage_finite(inputFile,outputFile)
copyfile(inputFile,outputFile);
v=spm_vol(outputFile); data=spm_read_vols(v);
data(~isfinite(data))=0;
spm_write_vol(v,data);
end

function result=volume_is_finite(file)
result=all(isfinite(spm_read_vols(spm_vol(file))),'all');
end

function changed=sanitize_in_place(file)
v=spm_vol(file); data=spm_read_vols(v); changed=any(~isfinite(data),'all');
if changed
    data(~isfinite(data))=0;
    spm_write_vol(v,data);
end
end
