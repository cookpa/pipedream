pipedream
=========

PipeDream - open source neuroimaging pipelines

Installation:

```
git clone git@github.com:cookpa/pipedream.git

cp pipedream/config/pipedream_config_example.sh  pipedream/config/pipedream_config.sh
```

Then edit `pipedream/config/pipedream_config.sh`

Call code via the .sh wrappers, eg

```
pipedream/dicom2series/dicom2series.sh
```

The code here is mostly for pre-processing, most advanced processing has been relocated to ANTs. 

See 

  http://stnava.github.io/ANTs/

Specifically, antsCorticalThickness.sh replaces the T1 cortical thickness pipeline
that was previously implemented here.

The main use of Pipedream is for data organization using GDCM (to sort data) and
dcm2nii (to convert it to Nifti). 
