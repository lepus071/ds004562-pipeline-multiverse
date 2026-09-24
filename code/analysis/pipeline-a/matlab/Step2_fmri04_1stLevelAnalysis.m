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
mkdir('spm-bold'); cd('spm-bold');
pathBOLD = pwd;
mkdir('bold-1stlevel'); cd('bold-1stlevel');
path1LV = pwd;


%% analysis
cd(currentPath);

disp('defaults');
spm('defaults','FMRI');
disp('init');
spm_jobman('initcfg');

directions = {'rightward', 'upward', 'leftward', 'downward'};

mirror_contrast_vector = [];
rot_pos90_contrast_vector = [];
rot_neg90_contrast_vector = [];
session_start_contrast_vector = [];
session_change_contrast_vector = [];
score_contrast_vector = [];
   
for nsub = 1:length(prepSubjFolders)
    % make subject directory
    cd(path1LV); mkdir(prepSubjFolders(nsub).name);

    % ready func images
    frame = 0;
    cd([prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'func']);
    funcFilePath = conn_dir('s8wau*bold.nii');
    ninfo = niftiinfo(funcFilePath);
    clear scanFileList
    for ff = 1:ninfo.ImageSize(4)
        frame = frame+1;
        scanFileList{frame,1}=[funcFilePath ',' num2str(ff)];  %#ok<SAGROW>
    end
    % ready movement covariates
    cd([prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'func']);
    rp_file = dir('rp*.txt');
    move_cov = readmatrix(rp_file(1).name);
    outlier_file = dir('art_regression_outliers_ausub-*_ses-02fmri_task-adaptation_bold.mat');
    load(outlier_file.name);
    outlier_cov = R;
    
    % event file
    cd([pathBIDS filesep prepSubjFolders(nsub).name]); cd('ses-02fmri'); cd('func');
    eventfile = dir('sub*events.tsv');
    eventtable = readtable(eventfile.name,'FileType','text','TreatAsMissing','n/a');
    onset = eventtable.onset;
    duration = eventtable.duration;
    trial_type = eventtable.trial_type;
    session_number = eventtable.session_number;
    session_type = eventtable.session_type;

    clear matlabbatch
    % model specification    
    matlabbatch{1}.spm.stats.fmri_spec.dir = {fullfile(path1LV, prepSubjFolders(nsub).name)};
    matlabbatch{1}.spm.stats.fmri_spec.timing.units = 'secs';
    matlabbatch{1}.spm.stats.fmri_spec.timing.RT = 2.3;
    matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t = 16;
    matlabbatch{1}.spm.stats.fmri_spec.timing.fmri_t0 = 8;
    matlabbatch{1}.spm.stats.fmri_spec.sess.scans = scanFileList;
    % condition (convoluted with hrf)
    
    regressNum = 0;
    
    session_change_contrast_vector = zeros(15,1);
    for nses = 1:15
        if nses > 1
            temp_prev_ses_type = unique(session_type(session_number == (nses-1))); temp_prev_ses_type = temp_prev_ses_type{1};
            temp_ses_type = unique(session_type(session_number == nses)); temp_ses_type = temp_ses_type{1};
            if strcmp(temp_prev_ses_type,temp_ses_type)
                session_change_contrast_vector(nses) = -1;
            else
                session_change_contrast_vector(nses) = 1;
            end
        end
    end
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'session_start';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = onset(strcmp(trial_type,'start_session'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = duration(strcmp(trial_type,'start_session'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod.name = 'task switch';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod.param = session_change_contrast_vector;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod.poly = 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    
    is_tooExplored = squeeze(is_tooExplored_trial(nsub,2,:,:));
    is_tooExplored = is_tooExplored';
    is_tooExplored = is_tooExplored(:);
    
    ses_name = 'rotation+90';
    temp_onset = onset(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    temp_duration = duration(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    ses_idx = strcmp(session_type(strcmp(trial_type,'erasing')),ses_name);
    temp_onset(is_tooExplored(ses_idx)) = [];
    temp_duration(is_tooExplored(ses_idx)) = [];
    
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'rotation+90';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    
    ses_name = 'rotation-90';
    temp_onset = onset(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    temp_duration = duration(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    ses_idx = strcmp(session_type(strcmp(trial_type,'erasing')),ses_name);
    temp_onset(is_tooExplored(ses_idx)) = [];
    temp_duration(is_tooExplored(ses_idx)) = [];
    
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'rotation-90';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    
    ses_name = 'mirror';
    temp_onset = onset(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    temp_duration = duration(strcmp(trial_type,'erasing') & strcmp(session_type,ses_name));
    ses_idx = strcmp(session_type(strcmp(trial_type,'erasing')),ses_name);
    temp_onset(is_tooExplored(ses_idx)) = [];
    temp_duration(is_tooExplored(ses_idx)) = [];
    
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'mirror';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'score';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = onset(strcmp(trial_type,'score'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = duration(strcmp(trial_type,'score'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    
    regressNum = regressNum + 1;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'session end';
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = onset(strcmp(trial_type,'end_session'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = duration(strcmp(trial_type,'end_session'));
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
    matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;

    
    temp_onset = onset(strcmp(trial_type,'erasing'));
    temp_duration = duration(strcmp(trial_type,'erasing'));
    
    for temp_i = find(is_tooExplored)'
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'erasing_too_explored_';
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset(temp_i);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration(temp_i);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
    end
    

    matlabbatch{1}.spm.stats.fmri_spec.sess.multi = {''};
    % regressors for covariate
    regressNum = 0;
    for ii = 1:6
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).name = ['Move ' num2str(ii,'%02d')];
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).val = move_cov(:,ii);
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).name = ['Move ' num2str(ii,'%02d') ' (grad)'];
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).val = gradient(move_cov(:,ii));
    end
    % outlier scan (?P)
    for ii = 1:size(outlier_cov,2)
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).name = ['Outlier ' num2str(ii,'%02d')];
        matlabbatch{1}.spm.stats.fmri_spec.sess.regress(regressNum).val = outlier_cov(:,ii);
    end

    matlabbatch{1}.spm.stats.fmri_spec.sess.multi_reg = {''};
    matlabbatch{1}.spm.stats.fmri_spec.sess.hpf = 128;
    matlabbatch{1}.spm.stats.fmri_spec.fact = struct('name', {}, 'levels', {});
    matlabbatch{1}.spm.stats.fmri_spec.bases.hrf.derivs = [0 0];
    matlabbatch{1}.spm.stats.fmri_spec.volt = 1;
    matlabbatch{1}.spm.stats.fmri_spec.global = 'None';
    matlabbatch{1}.spm.stats.fmri_spec.mthresh = 0.8;
    matlabbatch{1}.spm.stats.fmri_spec.mask = {''};
    matlabbatch{1}.spm.stats.fmri_spec.cvi = 'AR(1)';
    % estimate
    matlabbatch{2}.spm.stats.fmri_est.spmmat(1) = cfg_dep('fMRI model specification: SPM.mat File', substruct('.','val', '{}',{1}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
    matlabbatch{2}.spm.stats.fmri_est.write_residuals = 0;
    matlabbatch{2}.spm.stats.fmri_est.method.Classical = 1;
    % contrast manager
    matlabbatch{3}.spm.stats.con.spmmat(1) = cfg_dep('Model estimation: SPM.mat File', substruct('.','val', '{}',{2}, '.','val', '{}',{1}, '.','val', '{}',{1}), substruct('.','spmmat'));
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.name = 'erasing rotation+90';
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.weights = [0, 0, 1];
    matlabbatch{3}.spm.stats.con.consess{1}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.consess{2}.tcon.name = 'erasing rotation-90';
    matlabbatch{3}.spm.stats.con.consess{2}.tcon.weights = [0, 0, 0, 1];
    matlabbatch{3}.spm.stats.con.consess{2}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.consess{3}.tcon.name = 'erasing mirror';
    matlabbatch{3}.spm.stats.con.consess{3}.tcon.weights = [0, 0, 0, 0, 1];
    matlabbatch{3}.spm.stats.con.consess{3}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.consess{4}.tcon.name = 'session start';
    matlabbatch{3}.spm.stats.con.consess{4}.tcon.weights = [1];
    matlabbatch{3}.spm.stats.con.consess{4}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.consess{5}.tcon.name = 'session change';
    matlabbatch{3}.spm.stats.con.consess{5}.tcon.weights = [0, 1];
    matlabbatch{3}.spm.stats.con.consess{5}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.consess{6}.tcon.name = 'score';
    matlabbatch{3}.spm.stats.con.consess{6}.tcon.weights = [0, 0, 0, 0, 0, 1];
    matlabbatch{3}.spm.stats.con.consess{6}.tcon.sessrep = 'none';
    matlabbatch{3}.spm.stats.con.delete = 0;
    

    disp('run');
    spm_jobman('run', matlabbatch);
end
