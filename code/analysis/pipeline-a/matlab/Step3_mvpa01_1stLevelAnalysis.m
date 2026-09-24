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
mkdir('spm-mvpa'); cd('spm-mvpa');
pathBOLD = pwd;
mkdir('glm-1stlevel'); cd('glm-1stlevel');
path1LV = pwd;


%% analysis
cd(currentPath);

disp('defaults');
spm('defaults','FMRI');
disp('init');
spm_jobman('initcfg');

directions = {'rightward', 'upward', 'leftward', 'downward'};
   
for nsub = 1:length(prepSubjFolders)
    % make subject directory
    cd(path1LV); mkdir(prepSubjFolders(nsub).name);

    % ready func images
    frame = 0;
    cd([prepSubjFolders(nsub).folder filesep prepSubjFolders(nsub).name filesep 'func']);
    funcFilePath = conn_dir('s2au*bold.nii');
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
    for nses = 1:15
        temp_onset = onset(session_number == nses);
        temp_duration = duration(session_number == nses);
        temp_ses_type = unique(session_type(session_number == nses)); temp_ses_type = temp_ses_type{1};
        temp_stimulus_direction = eventtable.stimulus_direction(session_number == nses);
        temp_is_tooExplored = squeeze(is_tooExplored_trial(nsub,2,nses,:));
        
        % regressor for session start
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = ['session_start_' temp_ses_type];
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset(1);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration(1);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
        
        % regressor for erasing
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'first trial (excluded)';
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset(2);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration(2);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
        
        temp_erasing_onset = temp_onset(3:18);
        temp_erasing_duration = temp_duration(3:18);
        temp_stimulus_direction = temp_stimulus_direction(3:18);
        temp_is_tooExplored(1) = [];
        
        for n_type = 1:4
            regressNum = regressNum + 1;
            temp_idx = strcmp(temp_stimulus_direction,directions{n_type});
            temp_idx(temp_is_tooExplored) = false;
            if ~any(temp_idx)
                error('No valid trial!!! Something went wrong!!!');
            end
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = ['erasing_' temp_ses_type '_' directions{n_type}];
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_erasing_onset(temp_idx);
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_erasing_duration(temp_idx);
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
        end
        
        for temp_i = find(temp_is_tooExplored)'
            regressNum = regressNum + 1;
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = ['erasing_too_explored_' temp_ses_type '_' directions{n_type}];
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_erasing_onset(temp_i);
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_erasing_duration(temp_i);
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
            matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
        end
        
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'score';
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset(19);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration(19);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).tmod = 0;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).pmod = struct('name', {}, 'param', {}, 'poly', {});
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).orth = 1;
        
        regressNum = regressNum + 1;
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).name = 'session end';
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).onset = temp_onset(20);
        matlabbatch{1}.spm.stats.fmri_spec.sess.cond(regressNum).duration = temp_duration(20);
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

    disp('run');
    spm_jobman('run', matlabbatch);
end
