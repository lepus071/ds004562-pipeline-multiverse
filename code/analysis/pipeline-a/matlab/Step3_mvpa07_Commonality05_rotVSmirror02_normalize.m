%% initialize
clear; clc;

currentPath = pwd;
cd ../temp
load('tempFileForAnalysis.mat');

cd(pathBIDS);
cd derivatives
pathDeriv = pwd;

cd(pathDeriv);
cd('spm-preproc'); % For saving preprocessed file from SPM
pathPrepFile = pwd;
prepSubjFolders = dir('sub*');

cd(pathDeriv);
cd('behavior');
pathBehav = pwd;
load('beh_results.mat');

cd(pathDeriv);
cd('spm-mvpa');
cd('glm-1stlevel');
path1LV = pwd;
results1st_subj = dir('sub-*');

cd ..
cd('MVPA_TaskContext_rotationVSmirror');
pathMVPA = pwd;

%% 
cd(currentPath);

disp('defaults');
spm('defaults','FMRI');
disp('init');
spm_jobman('initcfg');

for nsub = 1:length(prepSubjFolders)
    matlabbatch = cell(1);
    matlabbatch{1}.spm.spatial.normalise.write.subj.def = {[prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'anat' filesep 'y_sub-' num2str(nsub,'%02d') '_ses-02fmri_T1w.nii']};
    matlabbatch{1}.spm.spatial.normalise.write.subj.resample = {[pathMVPA filesep prepSubjFolders(nsub).name filesep 'res_accuracy_minus_chance.nii']};
    matlabbatch{1}.spm.spatial.normalise.write.woptions.bb = [-78 -112 -70
                                                              78 76 85];
    matlabbatch{1}.spm.spatial.normalise.write.woptions.vox = [2 2 2];
    matlabbatch{1}.spm.spatial.normalise.write.woptions.interp = 4;
    matlabbatch{1}.spm.spatial.normalise.write.woptions.prefix = 'w';
    matlabbatch{2}.spm.spatial.smooth.data(1) = cfg_dep('Normalise: Write: Normalised Images (Subj 1)', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('()',{1}, '.','files'));
    matlabbatch{2}.spm.spatial.smooth.fwhm = [8 8 8];
    matlabbatch{2}.spm.spatial.smooth.dtype = 0;
    matlabbatch{2}.spm.spatial.smooth.im = 0;
    matlabbatch{2}.spm.spatial.smooth.prefix = 's8';
    
    disp('run');
    spm_jobman('run', matlabbatch);
end