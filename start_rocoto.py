##################################################################################
# License Statement:
#
# Copyright 2022 Colin Grudzien, cgrudzien@ucsd.edu
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.
# 
##################################################################################
# imports
import os
import time
from rocoto_utilities import run_rocotorun, run_rocotoboot

##################################################################################
# initiate rocoto
run_rocotorun()

# boot first cold start
cycle = "201808121200"
task_list = "gsi"
run_rocotoboot(cycle, task_list)

# monitor and advance the jobs
while (True):
    time.sleep(60)
    run_rocotorun()
