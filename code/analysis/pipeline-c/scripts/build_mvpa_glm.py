#!/usr/bin/env python3
"""Build the 60 condition-beta images required by Arm C decoding.

This leaves the earlier exploratory Arm C GLM untouched. It mirrors the
published block x direction model, using Nilearn on Arm B's staged fMRIPrep
BOLD and the frozen explicit Arm B-grid mask.
"""
from __future__ import annotations
import argparse, json, time
from pathlib import Path
import h5py
import nibabel as nib
import numpy as np
import pandas as pd
from scipy.io import loadmat
from nilearn.glm.first_level import FirstLevelModel
from nilearn.image import concat_imgs

ROOT=Path('<DATA_ROOT>')
CONTEXTS=['rotation+90','rotation-90','mirror']
DIRECTIONS=['leftward','rightward','upward','downward']

def files(sub):
    label=f'sub-{sub}'; stem=f'{label}_ses-02fmri_task-adaptation'
    staged=ROOT/'derivatives/arm-b/glm-inputs'/label/'func'
    source=staged/f's2{stem}_space-T1w_desc-preproc_bold.nii'
    cached=Path('<SCRATCH_ROOT>/arm-c-bold-cache')/f'{label}.nii'
    bold=cached if cached.is_file() else source
    return (bold,
            staged/f'{stem}_arm-b_regressors.mat',
            ROOT/'ds004562'/label/'ses-02fmri'/'func'/f'{stem}_events.tsv',
            ROOT/'derivatives/common-searchlight-masks'/label/'arm-b_explicit_mask.nii')

def build_events(sub, event_file):
    raw=pd.read_csv(event_file,sep='\t')
    bad=loadmat(ROOT/'ds004562/derivatives/behavior/beh_results.mat')['is_tooExplored_trial']
    sidx=int(sub)-1
    rows=[]; conditions=[]
    blocks_by={(ctx,d):[] for ctx in CONTEXTS for d in DIRECTIONS}
    for block in range(1,16):
        b=raw[raw.session_number.eq(block)].copy()
        ctx=str(b.session_type.iloc[0])
        start=b[b.trial_type.eq('start_session')].iloc[0]
        score=b[b.trial_type.eq('score')].iloc[0]
        end=b[b.trial_type.eq('end_session')].iloc[0]
        er=b[b.trial_type.eq('erasing')].reset_index(drop=True)
        assert len(er)==17
        flags=bad[sidx,1,block-1,:].astype(bool)
        assert len(flags)==17
        for tag,ev in [('start',start),('score',score),('end',end)]:
            rows.append({'onset':ev.onset,'duration':ev.duration,'trial_type':f'nuis_{tag}_b{block:02d}'})
        first=er.iloc[0]
        rows.append({'onset':first.onset,'duration':first.duration,'trial_type':f'nuis_first_b{block:02d}'})
        keep=er.iloc[1:].copy(); keep_flags=flags[1:]
        for j,(_,ev) in enumerate(keep.iterrows(),start=2):
            if keep_flags[j-2]:
                rows.append({'onset':ev.onset,'duration':ev.duration,'trial_type':f'nuis_bad_b{block:02d}_t{j:02d}'})
        for direction in DIRECTIONS:
            name=f'erasing_{ctx}_{direction}_b{block:02d}'
            selected=keep[(keep.stimulus_direction.eq(direction)) & (~keep_flags)]
            if selected.empty:
                raise RuntimeError(f'{sub} block {block} {ctx} {direction}: no valid trials')
            for _,ev in selected.iterrows():
                rows.append({'onset':ev.onset,'duration':ev.duration,'trial_type':name})
            blocks_by[(ctx,direction)].append((block,name,len(selected)))
    for ctx in CONTEXTS:
        for direction in DIRECTIONS:
            vals=blocks_by[(ctx,direction)]
            assert len(vals)==5,(ctx,direction,vals)
            for block,name,ntrials in vals:
                conditions.append({'context':ctx,'direction':direction,'block':block,
                                   'regressor':name,'n_trials':ntrials})
    return pd.DataFrame(rows).sort_values('onset'),conditions

def main(sub,n_jobs):
    t0=time.time(); label=f'sub-{sub}'
    bold,regfile,eventfile,mask=files(sub)
    for f in (bold,regfile,eventfile,mask):
        if not f.is_file(): raise FileNotFoundError(f)
    out=ROOT/'derivatives/arm-c/mvpa-glm-1stlevel'/label
    out.mkdir(parents=True,exist_ok=True)
    complete=out/'complete.json'
    if complete.exists():
        print(f'{label}: already complete'); return
    if any(out.iterdir()): raise RuntimeError(f'partial output exists, refusing overwrite: {out}')
    with h5py.File(regfile,'r') as h:
        conf=np.column_stack([np.asarray(h['move_cov']).T,
                              np.asarray(h['move_derivative_cov']).T,
                              np.asarray(h['R']).T])
    if conf.shape[0]!=1360 or not np.isfinite(conf).all(): raise RuntimeError('invalid confounds')
    confdf=pd.DataFrame(conf,columns=[f'confound_{i:03d}' for i in range(conf.shape[1])])
    events,conditions=build_events(sub,eventfile)
    events.to_csv(out/'model_events.tsv',sep='\t',index=False)
    pd.DataFrame(conditions).to_csv(out/'beta_manifest.tsv',sep='\t',index=False)
    model=FirstLevelModel(t_r=2.3,slice_time_ref=0.5,hrf_model='spm',drift_model='cosine',
        high_pass=1/128,noise_model='ar1',standardize=False,smoothing_fwhm=None,
        mask_img=str(mask),minimize_memory=True,verbose=0,n_jobs=n_jobs)
    model.fit(str(bold),events=events[['onset','duration','trial_type']],confounds=confdf)
    model.design_matrices_[0].to_csv(out/'design_matrix.tsv',sep='\t',index=False)
    betas=[]
    for i,c in enumerate(conditions,1):
        print(f'{label}: beta {i:02d}/60 {c["regressor"]}',flush=True)
        betas.append(model.compute_contrast(c['regressor'],output_type='effect_size'))
    series=concat_imgs(betas,auto_resample=False)
    series.set_data_dtype(np.float32)
    nib.save(series,out/'condition_betas.nii.gz')
    data=np.asanyarray(series.dataobj)
    meta={'tool':'nilearn','nilearn_version':__import__('nilearn').__version__,'subject':sub,
          'n_scans':1360,'n_jobs':n_jobs,'n_confounds':int(conf.shape[1]),'n_condition_betas':60,
          'contexts':CONTEXTS,'directions':DIRECTIONS,'finite':bool(np.isfinite(data).all()),
          'shape':list(series.shape),'runtime_seconds':time.time()-t0,
          'source_bold':str(bold),'explicit_mask':str(mask)}
    if not meta['finite']: raise RuntimeError('non-finite beta series')
    complete.write_text(json.dumps(meta,indent=2))
    print(json.dumps(meta,indent=2))

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--subject',required=True); ap.add_argument('--n-jobs',type=int,default=1)
    a=ap.parse_args(); main(str(a.subject).zfill(2),a.n_jobs)
