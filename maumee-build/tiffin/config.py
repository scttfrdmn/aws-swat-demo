'''----------------- QSWAT+ Workflow Settings: Tiffin River (Maumee tributary) -----------'''
Project_Name          = "tiffin"
Model_2_config        = False
'''---------------------------- File Names ---------------------------'''
Topography            = "srtm_30m.tif"
Soils                 = "soil.tif"
Land_Use              = "landuse.tif"
Soil_Lookup           = "soil_lookup.csv"
Landuse_Lookup        = "landuse_lookup.csv"
Usersoil              = "usersoil.csv"
Outlets               = "outlets.shp"
'''---------------------------  Project Options  ----------------------'''
Ws_Thresholds_Type    = 1
Channel_Threshold     = 500
Stream_Threshold      = 500
Out_Snap_Threshold    = 300
Burn_In_Shape         = ""
Slope_Classes         = "[0, 9999]"
HRU_Filter_Method     = 3
HRU_Thresholds_Type   = 2
Land_Soil_Slope_Thres = ""
Target_Area           = 0
Target_Value          = 0
ET_Method             = 2
Routing_Method        = 1
Routing_Timestep      = 1
launduse_management_settings = []
reservoir_management_settings = []
Start_Year            = 2015
End_Year              = 2018
Warm_Up_Period        = 1
Print_CSV             = 1
Print_Objects         = {
                             "channel_sd"   : [1, 2, 3, 4],
                        }
Executable_Type       = 1
Cal_File              = ""
Calibrate               = True
Calibration_Config_File = "calibration_config.csv"
Number_of_Runs          = 80
Number_of_Processes     = 8
Make_Figures            = False
Keep_Log                = True
'''---------------------------  Settings End  -----------------------'''
