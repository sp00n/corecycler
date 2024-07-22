================================================================================
Copyright 2001-2021 Intel Corporation.

This software and the related  documents are Intel  copyrighted  materials,  and
your use  of them  is governed  by the  express  license under  which  they were
provided to you (License).  Unless the  License provides otherwise,  you may not
use,  modify, copy,  publish, distribute,  disclose or transmit this software or
the related documents without Intel's prior written permission.

This software and the  related documents are provided as is,  with no express or
implied warranties, other than those that are expressly stated in the License.
================================================================================

======================================================================
 -- High Performance Computing Linpack Benchmark (HPL)                
    HPL - 2.3 - December 2, 2018                        
    Antoine P. Petitet                                                
    University of Tennessee, Knoxville                                
    Innovative Computing Laboratory                                 
    (C) Copyright 2000-2008 All Rights Reserved                       
                                                                      
 -- Copyright notice and Licensing terms:                             
                                                                      
 Redistribution  and  use in  source and binary forms, with or without
 modification, are  permitted provided  that the following  conditions
 are met:                                                             
                                                                      
 1. Redistributions  of  source  code  must retain the above copyright
 notice, this list of conditions and the following disclaimer.        
                                                                      
 2. Redistributions in binary form must reproduce  the above copyright
 notice, this list of conditions,  and the following disclaimer in the
 documentation and/or other materials provided with the distribution. 
                                                                      
 3. All  advertising  materials  mentioning  features  or  use of this
 software must display the following acknowledgement:                 
 This  product  includes  software  developed  at  the  University  of
 Tennessee, Knoxville, Innovative Computing Laboratory.             
                                                                      
 4. The name of the  University,  the name of the  Laboratory,  or the
 names  of  its  contributors  may  not  be used to endorse or promote
 products  derived   from   this  software  without  specific  written
 permission.                                                          
                                                                      
 -- Disclaimer:                                                       
                                                                      
 THIS  SOFTWARE  IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,  INCLUDING,  BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE UNIVERSITY
 OR  CONTRIBUTORS  BE  LIABLE FOR ANY  DIRECT,  INDIRECT,  INCIDENTAL,
 SPECIAL,  EXEMPLARY,  OR  CONSEQUENTIAL DAMAGES  (INCLUDING,  BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA OR PROFITS; OR BUSINESS INTERRUPTION)  HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT,  STRICT LIABILITY,  OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
======================================================================

===============================================================================

       Intel(R) Distribution for LINPACK* Benchmark
       *Other names and brands may be claimed as the property of others.
===============================================================================

Package Contents 
----------------

This package contains Intel(R) Distribution for LINPACK* Benchmark.
It is optimized for Intel(R) Xeon(R) and Intel(R) Xeon Phi(TM) processors. 
First generation of Intel(R) Xeon Phi(TM) Product Family (codename Knights
Corner) is not supported.

Pre-built binaries linked with Intel(R) MPI Library are included in this
package. In addition, Intel(R) Distribution for LINPACK* Benchmark binary
linked with a third party MPI implementation can be created using the Intel(R)
oneAPI Math Kernel Library (oneMKL) MPI wrappers.

The package contains the following files:

COPYRIGHT                 : Original Netlib HPL copyright document

readme.txt                : This document

runme_intel64_dynamic.bat : Run script for dynamically linked MPI 

runme_intel64_prv.bat     : Script used by above script

xhpl_intel64_dynamic.exe  : Intel(R) Distribution for LINPACK* Benchmark binary
                            dynamically linked with Intel(R) MPI Library

HPL.dat                   : HPL configuration file

HPL_main.c                : Source code required to build Intel(R) Distribution
                            for LINPACK* Benchmark binary with third party MPI
                            implementation.

libhpl_intel64.lib        : Library file required to build Intel(R) Distribution
                            for LINPACK* Benchmark binary with third party MPI
                            implementation. 

Make.Windows_Intel64      : Makefile for Netlib HPL to build Windows binary with nmake

Blocking size (NB) recommendation
---------------------------------

Recommended blocking sizes (NB in HPL.dat) are listed below for various Intel(R) 
architectures:

Intel(R) Xeon(R) Processor X56*/E56*/E7-*/E7*/X7*                             : 256
Intel(R) Xeon(R) Processor E26*/E26* v2                                       : 256
Intel(R) Xeon(R) Processor E26* v3/E26* v4                                    : 192
Intel(R) Core(TM) i3 Processor                                                : 192
Intel(R) Core(TM) i5 Processor                                                : 192
Intel(R) Core(TM) i7 Processor                                                : 192
Intel(R) Xeon Phi(TM) Processor 72*                                           : 336
Intel(R) Xeon(R) Scalable Processors                                          : 384

Building Intel(R) Distribution for LINPACK* Benchmark for third party MPI
-------------------------------------------------------------

After setting MPI environment, please run following command on this directory.

$> SET MKL_DIRS=%MKLROOT%\lib
$> SET MKL_LIBS=%MKL_DIRS%\mkl_intel_lp64.lib %MKL_DIRS%\mkl_sequential.lib %MKL_DIRS%\mkl_core.lib
$> mpicc -I%MKLROOT%\include /Fexhpl HPL_main.c %MKLROOT%\share\mkl\interfaces\mklmpi\mklmpi-impl.c libhpl_intel64.lib %MKL_LIBS%

Building Intel(R) Distribution for LINPACK* Benchmark from source code
----------------------------------------------

Netlib HPL source code can be obtained from

    http://www.netlib.org/benchmark/hpl/

After extracting source code, 

1. Copy Make.Windows_Intel64 into HPL source code

     $> cp Make.Windows_Intel64 .

2. Edit Make.Windows_intel64 appropriately

3. Build HPL binary

     $> nmake -f Make.Windows_Intel64

4. Binary will be located in current directory

---
*Other names and brands may be claimed as the property of others.
