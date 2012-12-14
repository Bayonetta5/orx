# GNU Make project makefile autogenerated by Premake
ifndef config
  config=debug32
endif

ifndef verbose
  SILENT = @
endif

CC = gcc
CXX = g++
AR = ar

ifndef RESCOMP
  ifdef WINDRES
    RESCOMP = $(WINDRES)
  else
    RESCOMP = windres
  endif
endif

ifeq ($(config),debug32)
  OBJDIR     = obj/x32/Debug/09_Scrolling
  TARGETDIR  = ../../../bin/linux32
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += -D__orxDEBUG__
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -m32
  CXXFLAGS  += $(CFLAGS) -fno-exceptions
  LDFLAGS   += -L../../../lib/linux32 -m32 -L/usr/lib32 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorxd
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

ifeq ($(config),profile32)
  OBJDIR     = obj/x32/Profile/09_Scrolling
  TARGETDIR  = ../../../bin/linux32
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += -D__orxPROFILER__
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -O2 -m32 -fschedule-insns
  CXXFLAGS  += $(CFLAGS) -fno-exceptions -fno-rtti
  LDFLAGS   += -L../../../lib/linux32 -m32 -L/usr/lib32 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorxp
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

ifeq ($(config),release32)
  OBJDIR     = obj/x32/Release/09_Scrolling
  TARGETDIR  = ../../../bin/linux32
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += 
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -O2 -m32 -fschedule-insns
  CXXFLAGS  += $(CFLAGS) -fno-exceptions -fno-rtti
  LDFLAGS   += -L../../../lib/linux32 -m32 -L/usr/lib32 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorx
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

ifeq ($(config),debug64)
  OBJDIR     = obj/x64/Debug/09_Scrolling
  TARGETDIR  = ../../../bin/linux64
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += -D__orxDEBUG__
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -m64
  CXXFLAGS  += $(CFLAGS) -fno-exceptions
  LDFLAGS   += -L../../../lib/linux64 -m64 -L/usr/lib64 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorxd
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

ifeq ($(config),profile64)
  OBJDIR     = obj/x64/Profile/09_Scrolling
  TARGETDIR  = ../../../bin/linux64
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += -D__orxPROFILER__
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -O2 -m64 -fschedule-insns
  CXXFLAGS  += $(CFLAGS) -fno-exceptions -fno-rtti
  LDFLAGS   += -L../../../lib/linux64 -m64 -L/usr/lib64 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorxp
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

ifeq ($(config),release64)
  OBJDIR     = obj/x64/Release/09_Scrolling
  TARGETDIR  = ../../../bin/linux64
  TARGET     = $(TARGETDIR)/09_Scrolling
  DEFINES   += 
  INCLUDES  += -I../../../include
  CPPFLAGS  += -MMD -MP $(DEFINES) $(INCLUDES)
  CFLAGS    += $(CPPFLAGS) $(ARCH) -msse2 -ffast-math -g -O2 -m64 -fschedule-insns
  CXXFLAGS  += $(CFLAGS) -fno-exceptions -fno-rtti
  LDFLAGS   += -L../../../lib/linux64 -m64 -L/usr/lib64 -Wl,-rpath ./ -Wl,--export-dynamic
  RESFLAGS  += $(DEFINES) $(INCLUDES) 
  LIBS      += -lorx
  LDDEPS    += 
  LINKCMD    = $(CC) -o $(TARGET) $(OBJECTS) $(RESOURCES) $(ARCH) $(LIBS) $(LDFLAGS)
  define PREBUILDCMDS
  endef
  define PRELINKCMDS
  endef
  define POSTBUILDCMDS
  endef
endif

OBJECTS := \
	$(OBJDIR)/09_Scrolling.o \

RESOURCES := \

SHELLTYPE := msdos
ifeq (,$(ComSpec)$(COMSPEC))
  SHELLTYPE := posix
endif
ifeq (/bin,$(findstring /bin,$(SHELL)))
  SHELLTYPE := posix
endif

.PHONY: clean prebuild prelink

all: $(TARGETDIR) $(OBJDIR) prebuild prelink $(TARGET)
	@:

$(TARGET): $(GCH) $(OBJECTS) $(LDDEPS) $(RESOURCES)
	@echo Linking 09_Scrolling
	$(SILENT) $(LINKCMD)
	$(POSTBUILDCMDS)

$(TARGETDIR):
	@echo Creating $(TARGETDIR)
ifeq (posix,$(SHELLTYPE))
	$(SILENT) mkdir -p $(TARGETDIR)
else
	$(SILENT) mkdir $(subst /,\\,$(TARGETDIR))
endif

$(OBJDIR):
	@echo Creating $(OBJDIR)
ifeq (posix,$(SHELLTYPE))
	$(SILENT) mkdir -p $(OBJDIR)
else
	$(SILENT) mkdir $(subst /,\\,$(OBJDIR))
endif

clean:
	@echo Cleaning 09_Scrolling
ifeq (posix,$(SHELLTYPE))
	$(SILENT) rm -f  $(TARGET)
	$(SILENT) rm -rf $(OBJDIR)
else
	$(SILENT) if exist $(subst /,\\,$(TARGET)) del $(subst /,\\,$(TARGET))
	$(SILENT) if exist $(subst /,\\,$(OBJDIR)) rmdir /s /q $(subst /,\\,$(OBJDIR))
endif

prebuild:
	$(PREBUILDCMDS)

prelink:
	$(PRELINKCMDS)

ifneq (,$(PCH))
$(GCH): $(PCH)
	@echo $(notdir $<)
ifeq (posix,$(SHELLTYPE))
	-$(SILENT) cp $< $(OBJDIR)
else
	$(SILENT) xcopy /D /Y /Q "$(subst /,\,$<)" "$(subst /,\,$(OBJDIR))" 1>nul
endif
	$(SILENT) $(CC) $(CFLAGS) -o "$@" -MF $(@:%.gch=%.d) -c "$<"
endif

$(OBJDIR)/09_Scrolling.o: ../../../src/09_Scrolling/09_Scrolling.c
	@echo $(notdir $<)
	$(SILENT) $(CC) $(CFLAGS) -o "$@" -MF $(@:%.o=%.d) -c "$<"

-include $(OBJECTS:%.o=%.d)
ifneq (,$(PCH))
  -include $(OBJDIR)/$(notdir $(PCH)).d
endif