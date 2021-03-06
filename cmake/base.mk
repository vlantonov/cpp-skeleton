# {{{ Variables

RM = rm -rf
CP = cp
SED = sed
RTAGS = rc
PROFILES = normal debug release asan msan tsan usan analyzer

v/build     := .build
v/generator := Unix Makefiles
v/profile   := $(or $(P),$(PROFILE),normal)
b/release   := -DCMAKE_BUILD_TYPE=Release
b/debug     := -DCMAKE_BUILD_TYPE=Debug
b/use_clang := -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang

b/builcmd:=$(MAKE)
b/buildfile:=Makefile
ifeq ($(v/generator), Ninja)
	b/builcmd:=ninja-build
	b/buildfile:=build.ninja
endif


# }}}
# {{{ Cores

v/procs:=4
OS:=$(shell uname -s)

ifeq ($(OS),Linux)
  v/procs:=$(shell grep -c ^processor /proc/cpuinfo)
endif
ifeq ($(OS),Darwin) # Assume Mac OS X
  v/procs:=$(shell system_profiler | awk '/Number Of CPUs/{print $4}{next;}')
endif
v/procs:= $(or $(J),$(JOBS),${v/procs})

# }}}

.PHONY: test 

all: ./${v/root}/${v/build}/$(v/profile)/${b/buildfile}
ifeq (${v/profile},analyzer)
	@scan-build $(MAKE) -j ${v/procs} -C ./${v/root}/${v/build}/$(v/profile)/${v/current}
else
	@$(b/builcmd) -j ${v/procs} -C ./${v/root}/${v/build}/$(v/profile)/${v/current} $(MAKECMDGOALS)
endif

# Defines the different build targets depending on the profiles
# $1: The build profiles
# $2: The cmake project flag
# $3: Prefix command before executing cmake (exe:scan-build)
define make_build
	@(mkdir -p ./${v/root}/${v/build}/$(strip $(1)))
	@(cd ./${v/root}/${v/build}/$(strip $(1)) && $(3) cmake $(2) -G "${v/generator}" ../../)

endef

./${v/root}/${v/build}/normal/${b/buildfile}:
	$(call make_build, normal, ${b/debug} -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DLCOV_COVERAGE=ON)

./${v/root}/${v/build}/release/${b/buildfile}:
	$(call make_build, release, ${b/release} -DLCOV_COVERAGE=ON)

./${v/root}/${v/build}/debug/${b/buildfile}:
	$(call make_build, debug, ${b/debug} -DLCOV_COVERAGE=ON)

./${v/root}/${v/build}/asan/${b/buildfile}:
	$(call make_build, asan, ${b/debug} ${b/use_clang} -DCLANG_ASAN=ON)

./${v/root}/${v/build}/msan/${b/buildfile}:
	$(call make_build, msan, ${b/debug} ${b/use_clang} -DCLANG_MSAN=ON)

./${v/root}/${v/build}/tsan/${b/buildfile}:
	$(call make_build, tsan, ${b/debug} ${b/use_clang} -DCLANG_TSAN=ON)

./${v/root}/${v/build}/usan/${b/buildfile}:
	$(call make_build, usan, ${b/debug} ${b/use_clang} -DCLANG_USAN=ON)

./${v/root}/${v/build}/analyzer/${b/buildfile}:
	$(call make_build, analyzer, -DCLANG_STATIC_ANALYZER=ON, scan-build)

# {{{ Target: tidy

tidy: ./${v/root}/${v/build}/normal/${b/buildfile}
ifeq (".","${v/root}")
	@$(PYTHON) cmake/utils/run-clang-tidy.py -p ./${v/root}/${v/build}/normal/ -j ${v/procs}
else
	$(error this target can only be called from the root directory)
endif

# }}}
# {{{ Target: format

format:
ifeq (".","${v/root}")
	@clang-format -i `git ls-files | find -not -path "./.build/*" -and \( -name "*.cpp" -or -name "*.hpp" -or -name "*.c" -or -name ".h" \) | tr "\n" " "`
else
	$(error this target can only be called from the root directory)
endif

git-format:
	@$(PYTHON) "${v/root}/cmake/utils/git-clang-format"

# }}}
# {{{ Target: ycm

ycm: ./${v/root}/${v/build}/normal/${b/buildfile}
ifeq (".","${v/root}")
	@$(CP) cmake/ycm_extra_conf.py .ycm_extra_conf.py
	@${SED} -i 's/__BUILD__/${v/build}/' .ycm_extra_conf.py
else
	$(error this target can only be called from the root directory)
endif

# }}}
# {{{ Target: rtags

rtags: ./${v/root}/${v/build}/normal/${b/buildfile}
ifeq (".","${v/root}")
	@$(RTAGS) -J ${v/build}/normal/
else
	$(error this target can only be called from the root directory)
endif

# }}}
# {{{ Target: ctags

ctags: ./${v/root}/${v/build}/normal/${b/buildfile}
ifeq (".","${v/root}")
	@ctags -o .tags
else
	$(error this target can only be called from the root directory)
endif

# }}}
# {{{ Target: etags

etags: ./${v/root}/${v/build}/normal/${b/buildfile}
ifeq (".","${v/root}")
	@ctags -e -o .tags
else
	$(error this target can only be called from the root directory)
endif

# }}}
# {{{ Target: distclean

# Distribution clean.
#
# The Goal is to clean the user setup from any generated files.
#
# First call make clean in order to remove any file that might have been copied into the
# source repository.
# After that remove all the directories under __BUILD__
distclean:
	@$(buildcmd) clean
	$(foreach profile, $(PROFILES), $(call make_distclean, $(profile)))

define make_distclean
	@echo "DISTCLEAN > $(strip $(1))"
	@$(RM) ./${v/root}/${v/build}/$(strip $(1))

endef

# }}}
# {{{ Target: help

help:
	@echo "USAGES EXAMPLE"
	@echo "--------------"
	@echo "... make PROFILE=asan test"
	@echo "... make P=debug check"
	@echo "... make valgrind"
	@echo ""
	@echo "TARGETS"
	@echo "--------"
	@echo "The following are some of the valid targets for this Makefile:"
	@echo "... clean, distclean, ycm, ctags, rtags, test, valgrind, tidy, format"
	@echo "... coverage,  git-format"
	@echo ""
	@echo "PARALLEL COMPILATION (JOBS)"
	@echo "-----------------------------"
	@echo "If the OS is Mac or Linux the number of core available will be "
	@echo "detected automatically."
	@echo "To override the value found  set 'J' or 'JOBS' to the number of jobs."
	@echo "... make J=12 "
	@echo ""
	@echo "PROFILES"
	@echo "--------"
	@echo "Available Profiles are:"
	@echo "... normal, debug, release, asan, msan, tsan, usan, analyzer"
	@echo ""
	@echo "Default profile: normal"
	@echo ""
	@echo "PROJECT ARCHITECTURE"
	@echo "--------------------"
	@echo " src/"
	@echo "  |--- lib1"
	@echo "  |     |--- include"
	@echo "  |     |     |--- lib1"
	@echo "  |     |           |--- subdirectory1"
	@echo "  |     |           |     |--- public_header.hpp"
	@echo "  |     |           |--- subdirectory2"
	@echo "  |     |                 |--- public_header.hpp"
	@echo "  |     |--- subdirectory1"
	@echo "  |     |     |--- private_header.hpp"
	@echo "  |     |     |--- files.cpp"
	@echo "  |     |--- subdirectory2"
	@echo "  |     |     |--- private_header.hpp"
	@echo "  |     |     |--- files.cpp"
	@echo "  |     |--- test"
	@echo "  |     |     |--- test.hpp"
	@echo "  |     |     |--- test.cpp"
	@echo ""
	@echo " Example of header inclusion in the test directory:"
	@echo "    > include <lib1/subdirectory1/public_header.hpp"
	@echo "    > include <subdirectory1/public_header.hpp"
	@echo "    > include <test/test.hpp"
	@echo ""
	@echo "DEBUGGING"
	@echo "---------"
	@echo "Verbose mode: make VERBOSE=1"
	@echo ""
	@echo "TESTING"
	@echo "-------"
	@echo "Unit test are copied in the lib/test directories under the name ctest"

# }}}
# {{{ Target: forwarding

# TODO use or
ifeq ($(findstring distclean,$(MAKECMDGOALS)),)
ifeq ($(findstring help,$(MAKECMDGOALS)),)
ifeq ($(findstring ycm,$(MAKECMDGOALS)),)
ifeq ($(findstring ctags,$(MAKECMDGOALS)),)
ifeq ($(findstring rtags,$(MAKECMDGOALS)),)
ifeq ($(findstring tidy,$(MAKECMDGOALS)),)
ifeq ($(findstring format,$(MAKECMDGOALS)),)
ifeq ($(findstring etags,$(MAKECMDGOALS)),)

$(MAKECMDGOALS): ./${v/root}/${v/build}/${v/profile}/${b/buildfile}
	@ $(b/builcmd) -j ${v/procs} -C ./${v/root}/${v/build}/${v/profile}/${v/current} $(MAKECMDGOALS)

endif
endif
endif
endif
endif
endif
endif
endif

# }}}
