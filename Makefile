TARGETS = oneapi
BUILD   = build
DEBUG   = build/debug

.PHONY: all debug clean $(TARGETS)

# general rules and targets
all: $(TARGETS)

debug: $(TARGETS:%=%-debug)

clean:
	rm -r -f test-* debug-* $(BUILD) Kokkos*.o libkokkos.a $(DEBUG) env.sh

$(BUILD):
	mkdir -p $(BUILD)

$(DEBUG):
	mkdir -p $(DEBUG)

# configure external tool here
BOOST_BASE  :=
TBB_BASE    :=
CUDA_BASE   := /usr/local/cuda-10.2
ONEAPI_BASE := /opt/intel/oneapi/compiler/latest/linux
DPCT_BASE   := /opt/intel/oneapi/dpcpp-ct/latest

# host compiler
CXX := g++
CXX_FLAGS := -O2 -std=c++14
CXX_DEBUG := -g
OMP_CXX_FLAGS := -fopenmp -foffload=disable
OMP_LD_FLAGS  := -fopenmp -foffload=disable

# CUDA compiler
ifdef CUDA_BASE
NVCC := $(CUDA_BASE)/bin/nvcc -ccbin $(CXX)
NVCC_FLAGS := -O2 -std=c++14 --expt-relaxed-constexpr -w --generate-code arch=compute_35,code=sm_35 --generate-code arch=compute_50,code=sm_50 --generate-code arch=compute_60,code=sm_60 --generate-code arch=compute_70,code=sm_70
NVCC_DEBUG := -g -lineinfo

# CUDA flags for the host linker
CUDA_LIBDIR   := $(CUDA_BASE)/lib64
CUDA_LD_FLAGS := -L$(CUDA_LIBDIR) -lcudart -lcuda
endif

# boost flags
ifdef BOOST_BASE
BOOST_CXX_FLAGS := -I$(BOOST_BASE)/include
else
BOOST_CXX_FLAGS :=
endif

# TBB flags
ifdef TBB_BASE
TBB_LIBDIR    := $(TBB_BASE)/lib
TBB_CXX_FLAGS := -I$(TBB_BASE)/include
TBB_LD_FLAGS  := -L$(TBB_LIBDIR) -ltbb -lrt
else
TBB_LIBDIR    :=
TBB_CXX_FLAGS :=
TBB_LD_FLAGS  := -ltbb -lrt
endif

# oneAPI flags
ifdef ONEAPI_BASE
ifneq ($(wildcard $(ONEAPI_BASE)/lib/libsycl.so),)
ONEAPI_LIBDIR := $(ONEAPI_BASE)/lib
else ifneq ($(wildcard $(ONEAPI_BASE)/lib64/libsycl.so),)
ONEAPI_LIBDIR := $(ONEAPI_BASE)/lib64
else
ONEAPI_BASE :=
endif
endif
ifdef ONEAPI_BASE
ONEAPI_CXX   := $(ONEAPI_BASE)/bin/clang++
ONEAPI_FLAGS := -fsycl -I$(DPCT_BASE)/include
HAVE_LLVM_11 := $(wildcard $(ONEAPI_BASE)/bin/clang-11)
ifdef HAVE_LLVM_11
ONEAPI_FLAGS := $(ONEAPI_FLAGS) -Wno-unknown-cuda-version
endif
ifdef CUDA_BASE
ONEAPI_CUDA_PLUGIN := $(wildcard $(ONEAPI_LIBDIR)/libpi_cuda.so)
ONEAPI_CUDA_FLAGS  := --cuda-path=$(CUDA_BASE)
endif
endif

# color highlights for ANSI terminals
GREEN  := '\033[32m'
RED    := '\033[31m'
YELLOW := '\033[38;5;220m'
WHITE  := '\033[97m'
RESET  := '\033[0m'

# force the recreation of the environment file any time the Makefile is updated, before building any other target
-include environment
.PHONY: environment

environment: env.sh

env.sh: Makefile
	@echo '#! /bin/bash' > $@
ifdef ONEAPI_LIBDIR
	@echo 'export PATH=$(ONEAPI_BASE)/bin:$$PATH' >> $@
endif
	@echo -n 'export LD_LIBRARY_PATH=' >> $@
ifdef TBB_LIBDIR
	@echo -n '$(TBB_LIBDIR):' >> $@
endif
ifdef CUDA_LIBDIR
	@echo -n '$(CUDA_LIBDIR):' >> $@
endif
ifdef ONEAPI_LIBDIR
	@echo -n '$(ONEAPI_LIBDIR):' >> $@
endif
	@echo '$$LD_LIBRARY_PATH' >> $@
	@echo -e $(GREEN)Environment file$(RESET) regenerated, load the new envirnment with
	@echo
	@echo -e \ \ $(WHITE)source env.sh$(RESET)
	@echo

ifdef CUDA_BASE
# CUDA implementation
cuda: test-cuda
	@echo -e $(GREEN)CUDA targets built$(RESET)

cuda-debug: debug-cuda
	@echo -e $(GREEN)CUDA debug targets built$(RESET)

$(BUILD)/rawtodigi_cuda.o: rawtodigi_cuda.cu | $(BUILD)
	$(NVCC) $(NVCC_FLAGS) -DDIGI_CUDA -o $@ -x cu -c $<

$(BUILD)/analyzer_cuda.o: analyzer_cuda.cc | $(BUILD)
	$(CXX) $(CXX_FLAGS) -DDIGI_CUDA -I$(CUDA_BASE)/include -o $@ -c $<

$(BUILD)/main_cuda.o: main_cuda.cc | $(BUILD)
	$(CXX) $(CXX_FLAGS) -DDIGI_CUDA -I$(CUDA_BASE)/include -o $@ -c $<

test-cuda: $(BUILD)/main_cuda.o $(BUILD)/analyzer_cuda.o $(BUILD)/rawtodigi_cuda.o
	$(CXX) $(CXX_FLAGS) -o $@ $+ -L$(CUDA_BASE)/lib64 -lcudart -lcuda

debug-cuda: main_cuda.cc rawtodigi_cuda.cu rawtodigi_cuda.h
	$(NVCC) $(NVCC_FLAGS) $(NVCC_DEBUG) -DDIGI_CUDA -o $@ main_cuda.cc rawtodigi_cuda.cu
else
cuda:
	@echo -e $(YELLOW)NVIDIA CUDA not found$(RESET), CUDA targets will not be built

cuda-debug:
	@echo -e $(YELLOW)NVIDIA CUDA not found$(RESET), CUDA debug targets will not be built

endif

ifdef ONEAPI_BASE
oneapi: test-oneapi test-oneapi-opencl test-oneapi-cuda
	@echo -e $(GREEN)Intel oneAPI targets built$(RESET)

oneapi-debug: debug-oneapi debug-oneapi-opencl debug-oneapi-cuda
	@echo -e $(GREEN)Intel oneAPI debug targets built$(RESET)

# Intel oneAPI implementation
test-oneapi-opencl: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=spir64-*-*-sycldevice $(CXX_FLAGS) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

debug-oneapi-opencl: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=spir64-*-*-sycldevice $(CXX_FLAGS) $(CXX_DEBUG) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

ifdef ONEAPI_CUDA_PLUGIN
test-oneapi-cuda: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=nvptx64-*-*-sycldevice $(ONEAPI_CUDA_FLAGS) $(CXX_FLAGS) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

debug-oneapi-cuda: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=nvptx64-*-*-sycldevice $(ONEAPI_CUDA_FLAGS) $(CXX_FLAGS) $(CXX_DEBUG) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

test-oneapi: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=nvptx64-*-*-sycldevice,spir64-*-*-sycldevice $(ONEAPI_CUDA_FLAGS) $(CXX_FLAGS) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

debug-oneapi: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=nvptx64-*-*-sycldevice,spir64-*-*-sycldevice $(ONEAPI_CUDA_FLAGS) $(CXX_FLAGS) $(CXX_DEBUG) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

else
test-oneapi-cuda:
	@echo -e $(YELLOW)NVIDIA CUDA support not found$(RESET), oneAPI targets using CUDA will not be built

debug-oneapi-cuda:
	@echo -e $(YELLOW)NVIDIA CUDA support not found$(RESET), oneAPI debug targets using CUDA will not be built

test-oneapi: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=spir64-*-*-sycldevice $(CXX_FLAGS) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

debug-oneapi: main_oneapi.cc analyzer_oneapi.cc analyzer_oneapi.h rawtodigi_oneapi.cc rawtodigi_oneapi.h
	$(ONEAPI_CXX) $(ONEAPI_FLAGS) -fsycl-targets=spir64-*-*-sycldevice $(CXX_FLAGS) $(CXX_DEBUG) -DDIGI_ONEAPI -o $@ main_oneapi.cc analyzer_oneapi.cc rawtodigi_oneapi.cc

endif

else
oneapi:
	@echo -e $(YELLOW)Intel oneAPI toolchain not found$(RESET), oneAPI targets will not be built

oneapi-debug:
	@echo -e $(YELLOW)Intel oneAPI toolchain not found$(RESET), oneAPI debug targets will not be built

endif
