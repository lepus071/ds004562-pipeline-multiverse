#!/usr/bin/env python3
"""Run valid Arm C visual and movement searchlights on 60 condition betas."""
from __future__ import annotations
import argparse,json,time
from pathlib import Path
import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.decoding import SearchLight
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

ROOT=Path('<DATA_ROOT>')
BRANCHES={
 'MVPA_VisualDirection_Alltask':{
  'labels':[1,2,3,4,1,2,3,4,1,2,3,4],
  'splits':[(0,40),(20,40),(40,0),(40,20),(10,50),(30,50),(50,10),(50,30),(0,20),(20,0),(10,30),(30,10)]},
 'MVPA_MoveDirection_Alltasks':{
  'labels':[2,1,3,4,1,2,4,3,4,3,1,2],
  'splits':[(0,50),(20,50),(50,0),(50,20),(10,40),(30,40),(40,10),(40,30),(0,20),(20,0),(10,30),(30,10)]}}

def ranges(start): return np.arange(start,start+10,dtype=int)

def main(sub,branch,n_jobs):
    t0=time.time(); label=f'sub-{sub}'
    base=ROOT/'derivatives/arm-c/mvpa-glm-1stlevel'/label
    betas=base/'condition_betas.nii.gz'; manifest=base/'beta_manifest.tsv'
    mask=ROOT/'derivatives/common-searchlight-masks'/label/'arm-b_explicit_mask.nii'
    for f in (betas,manifest,mask):
        if not f.is_file(): raise FileNotFoundError(f)
    out=ROOT/'derivatives/arm-c/mvpa'/branch/label; out.mkdir(parents=True,exist_ok=True)
    result=out/'accuracy_minus_chance.nii.gz'
    if result.exists(): print(f'{label} {branch}: already complete'); return
    if any(out.iterdir()): raise RuntimeError(f'partial output exists, refusing overwrite: {out}')
    man=pd.read_csv(manifest,sep='\t'); assert len(man)==60
    spec=BRANCHES[branch]; y=np.repeat(np.asarray(spec['labels']),5)
    cv=[(ranges(tr),ranges(te)) for tr,te in spec['splits']]
    for tr,te in cv:
        if set(y[tr])!=set(y[te]) or len(set(y[tr]))!=2: raise RuntimeError('invalid cross-classification split')
    estimator=make_pipeline(StandardScaler(),SVC(kernel='linear',C=1.0))
    sl=SearchLight(mask_img=str(mask),process_mask_img=str(mask),radius=9.0,
                   estimator=estimator,n_jobs=n_jobs,scoring='accuracy',cv=cv,verbose=0)
    sl.fit(str(betas),y)
    ref=nib.load(mask); scores=np.asarray(sl.scores_,dtype=np.float32)
    valid=np.asanyarray(ref.dataobj)>0
    if scores.shape!=ref.shape or not np.isfinite(scores[valid]).all(): raise RuntimeError('invalid scores')
    acc=nib.Nifti1Image(scores,ref.affine,ref.header); acc.set_data_dtype(np.float32)
    nib.save(acc,out/'accuracy.nii.gz')
    # Match Arms A/B: accuracy-minus-chance is stored in percentage points.
    amc=np.zeros_like(scores,dtype=np.float32); amc[valid]=(scores[valid]-0.5)*100.0
    outimg=nib.Nifti1Image(amc,ref.affine,ref.header); outimg.set_data_dtype(np.float32); nib.save(outimg,result)
    meta={'tool':'nilearn.SearchLight+sklearn.SVC','subject':sub,'branch':branch,
          'n_samples':60,'n_folds':12,'fold_train_n':10,'fold_test_n':10,
          'chance':0.5,'accuracy_minus_chance_unit':'percentage points',
          'radius_mm':9.0,'scaling':'StandardScaler within training fold',
          'n_jobs':n_jobs,'mask_voxels':int(valid.sum()),'finite_in_mask':True,
          'accuracy_min':float(scores[valid].min()),'accuracy_max':float(scores[valid].max()),
          'accuracy_mean':float(scores[valid].mean()),'runtime_seconds':time.time()-t0,
          'beta_order':'context [rotation+90,rotation-90,mirror] x direction [left,right,up,down] x 5 blocks'}
    (out/'metadata.json').write_text(json.dumps(meta,indent=2)); print(json.dumps(meta,indent=2))

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--subject',required=True); ap.add_argument('--branch',choices=list(BRANCHES),required=True); ap.add_argument('--n-jobs',type=int,default=12)
    a=ap.parse_args(); main(str(a.subject).zfill(2),a.branch,a.n_jobs)
