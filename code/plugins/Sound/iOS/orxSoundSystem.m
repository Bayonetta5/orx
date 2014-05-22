/* Orx - Portable Game Engine
 *
 * Copyright (c) 2008-2014 Orx-Project
 *
 * This software is provided 'as-is', without any express or implied
 * warranty. In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 *    1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 *
 *    2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 *
 *    3. This notice may not be removed or altered from any source
 *    distribution.
 */

/**
 * @file orxSoundSystem.m
 * @date 23/01/2010
 * @author iarwain@orx-project.org
 *
 * iOS sound system plugin implementation
 *
 */


#include "orxPluginAPI.h"
#include "stb_vorbis.c"
#import <AudioToolbox/AudioToolbox.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>


/** Module flags
 */
#define orxSOUNDSYSTEM_KU32_STATIC_FLAG_NONE      0x00000000 /**< No flags */

#define orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY     0x00000001 /**< Ready flag */
#define orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING 0x00000002 /**< Recording flag */

#define orxSOUNDSYSTEM_KU32_STATIC_MASK_ALL       0xFFFFFFFF /**< All mask */


/** Misc defines
 */
#define orxSOUNDSYSTEM_KU32_BANK_SIZE                     32
#define orxSOUNDSYSTEM_KS32_DEFAULT_STREAM_BUFFER_NUMBER  4
#define orxSOUNDSYSTEM_KS32_DEFAULT_STREAM_BUFFER_SIZE    4096
#define orxSOUNDSYSTEM_KS32_DEFAULT_RECORDING_FREQUENCY   44100
#define orxSOUNDSYSTEM_KF_DEFAULT_DIMENSION_RATIO         orx2F(0.01f)
#define orxSOUNDSYSTEM_KF_DEFAULT_THREAD_SLEEP_TIME       orx2F(0.001f)

#ifdef __orxDEBUG__

// WARNING: alASSERT() is temporarily deactivated as it's not working correctly on iOS 4.2 simulator
#define alASSERT()
//do                                                                      \
//{                                                                       \
//  ALenum eError = alGetError();                                         \
//  orxASSERT(eError == AL_NO_ERROR && "OpenAL error code: 0x%X", eError);\
//} while(orxFALSE)

#else /* __orxDEBUG__ */

#define alASSERT()

#endif /* __orxDEBUG__ */


/***************************************************************************
 * Structure declaration                                                   *
 ***************************************************************************/

/** Internal info structure
 */
typedef struct __orxSOUNDSYSTEM_INFO_t
{
  orxU32 u32ChannelNumber;
  orxU32 u32FrameNumber;
  orxU32 u32SampleRate;

} orxSOUNDSYSTEM_INFO;

/** Internal data structure
 */
typedef struct __orxSOUNDSYSTEM_DATA_t
{
  orxBOOL             bVorbis;

  orxSOUNDSYSTEM_INFO stInfo;

  union
  {
    struct
    {
      orxHANDLE       hResource;
      stb_vorbis     *pstFile;
    } vorbis;

    struct
    {
      ExtAudioFileRef oFileRef;
    } extaudio;
  };

#ifdef __orxDEBUG__
  orxU32              u32NameID;
#endif /* __orxDEBUG__ */

} orxSOUNDSYSTEM_DATA;

/** Internal sample structure
 */
struct __orxSOUNDSYSTEM_SAMPLE_t
{
  volatile ALuint     uiBuffer;
  orxFLOAT            fDuration;
  orxSOUNDSYSTEM_DATA stData;
};

/** Internal sound structure
 */
struct __orxSOUNDSYSTEM_SOUND_t
{
  orxBOOL   bIsStream;
  ALuint    uiSource;
  orxFLOAT  fDuration;

  union
  {
    /* Sample */
    struct
    {
      orxSOUNDSYSTEM_SAMPLE  *pstSample;
    };

    /* Stream */
    struct
    {
      orxLINKLIST_NODE        stNode;
      orxBOOL                 bDelete;
      orxBOOL                 bLoop;
      orxBOOL                 bStop;
      orxBOOL                 bPause;
      const orxSTRING         zReference;
      orxS32                  s32PacketID;
      orxSOUNDSYSTEM_DATA     stData;

      ALuint                  auiBufferList[0];
    };
  };
};

/** Static structure
 */
typedef struct __orxSOUNDSYSTEM_STATIC_t
{
  ALCdevice              *poDevice;           /**< OpenAL device */
  ALCdevice              *poCaptureDevice;    /**< OpenAL capture device */
  ALCcontext             *poContext;          /**< OpenAL context */
  orxBANK                *pstSampleBank;      /**< Sound bank */
  orxBANK                *pstSoundBank;       /**< Sound bank */
  orxFLOAT                fDimensionRatio;    /**< Dimension ratio */
  orxFLOAT                fRecDimensionRatio; /**< Reciprocal dimension ratio */
  orxU32                  u32StreamingThread; /**< Streaming thread */
  orxU32                  u32Flags;           /**< Status flags */
  ExtAudioFileRef         poRecordingFile;    /**< Recording file */
  orxLINKLIST             stStreamList;       /**< Stream list */
  orxSOUND_EVENT_PAYLOAD  stRecordingPayload; /**< Recording payload */
  orxS32                  s32StreamBufferSize;/**< Stream buffer size */
  orxS32                  s32StreamBufferNumber; /**< Stream buffer number */
  orxS16                 *as16StreamBuffer;   /**< Stream buffer */
  orxS16                 *as16RecordingBuffer;/**< Recording buffer */
  ALuint                 *auiWorkBufferList;  /**< Buffer list */
  orxTHREAD_SEMAPHORE    *pstStreamSemaphore; /**< Stream semaphore */

} orxSOUNDSYSTEM_STATIC;


/***************************************************************************
 * Static variables                                                        *
 ***************************************************************************/

/** Static data
 */
static orxSOUNDSYSTEM_STATIC sstSoundSystem;


/***************************************************************************
 * Private functions                                                       *
 ***************************************************************************/

static orxSTATUS orxFASTCALL orxSoundSystem_iOS_OpenRecordingFile()
{
  AudioStreamBasicDescription stFileInfo;
  NSString                   *poName;
  NSURL                      *poURL;
  orxU32                      u32Length;
  const orxCHAR              *zExtension;
  AudioFileTypeID             eFileFormat;
  orxSTATUS                   eResult;

  /* Gets file name's length */
  u32Length = orxString_GetLength(sstSoundSystem.stRecordingPayload.zSoundName);

  /* Gets extension */
  zExtension = (u32Length > 4) ? sstSoundSystem.stRecordingPayload.zSoundName + u32Length - 4 : orxSTRING_EMPTY;

  /* WAV? */
  if(orxString_ICompare(zExtension, ".wav") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileWAVEType;
  }
  /* CAF? */
  else if(orxString_ICompare(zExtension, ".caf") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileCAFType;
  }
  /* MP3? */
  else if(orxString_ICompare(zExtension, ".mp3") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileMP3Type;
  }
  /* AIFF? */
  else if(orxString_ICompare(zExtension, "aiff") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileAIFFType;
  }
  /* AC3? */
  else if(orxString_ICompare(zExtension, ".ac3") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileAC3Type;
  }
  /* AAC? */
  else if(orxString_ICompare(zExtension, ".aac") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFileAAC_ADTSType;
  }
  /* 3GP? */
  else if(orxString_ICompare(zExtension, "3gpp") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFile3GPType;
  }
  /* 3GP2? */
  else if(orxString_ICompare(zExtension, "3gp2") == 0)
  {
    /* Updates format */
    eFileFormat = kAudioFile3GP2Type;
  }
  /* WAV? */
  else
  {
    /* Updates format */
    eFileFormat = kAudioFileWAVEType;
  }

  /* Gets NSString */
  poName = [NSString stringWithCString:sstSoundSystem.stRecordingPayload.zSoundName encoding:NSUTF8StringEncoding];

  /* Gets associated URL */
  poURL = [NSURL fileURLWithPath:poName];

  /* Clears file info */
  orxMemory_Zero(&stFileInfo, sizeof(AudioStreamBasicDescription));

  /* Updates file info for 16bit PCM data */
  stFileInfo.mSampleRate        = sstSoundSystem.stRecordingPayload.stStream.stInfo.u32SampleRate;
  stFileInfo.mChannelsPerFrame  = (sstSoundSystem.stRecordingPayload.stStream.stInfo.u32ChannelNumber == 2) ? 2 : 1;
  stFileInfo.mFormatID          = kAudioFormatLinearPCM;
  stFileInfo.mFormatFlags       = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;
  stFileInfo.mBytesPerPacket    = 2 * stFileInfo.mChannelsPerFrame;
  stFileInfo.mFramesPerPacket   = 1;
  stFileInfo.mBytesPerFrame     = 2 * stFileInfo.mChannelsPerFrame;
  stFileInfo.mBitsPerChannel    = 16;

  /* Opens file */
  ExtAudioFileCreateWithURL((CFURLRef)poURL, eFileFormat, &stFileInfo, NULL, kAudioFileFlags_EraseFile, &(sstSoundSystem.poRecordingFile));

  /* Success? */
  if(sstSoundSystem.poRecordingFile)
  {
    /* Updates result */
    eResult = orxSTATUS_SUCCESS;
  }
  else
  {
    /* Updates result */
    eResult = orxSTATUS_FAILURE;

    /* Logs message */
    orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't open file <%s> to write recorded audio data. Sound recording is still in progress.", sstSoundSystem.stRecordingPayload.zSoundName);
  }

  /* Done! */
  return eResult;
}

static orxINLINE orxSTATUS orxSoundSystem_iOS_OpenFile(orxSOUNDSYSTEM_DATA *_pstData)
{
  orxSTATUS eResult = orxSTATUS_FAILURE;

  /* Opens file with vorbis */
  _pstData->vorbis.pstFile = stb_vorbis_open_file(_pstData->hResource, FALSE, NULL, NULL);

  /* Success? */
  if(_pstData->vorbis.pstFile != NULL)
  {
    stb_vorbis_info stFileInfo;

    /* Gets file info */
    stFileInfo = stb_vorbis_get_info(_pstData->vorbis.pstFile);

    /* Stores info */
    _pstData->stInfo.u32ChannelNumber = (orxU32)stFileInfo.channels;
    _pstData->stInfo.u32FrameNumber   = (orxU32)stb_vorbis_stream_length_in_samples(_pstData->vorbis.pstFile);
    _pstData->stInfo.u32SampleRate    = (orxU32)stFileInfo.sample_rate;

    /* Updates status */
    _pstData->bVorbis                 = orxTRUE;

    /* Updates result */
    eResult = orxSTATUS_SUCCESS;
  }
  else
  {
    NSString *poName;
    NSURL    *poURL;

    /* Gets NSString */
    poName = [NSString stringWithCString:orxResource_GetPath(zResourceLocation) encoding:NSUTF8StringEncoding];

    /* Gets associated URL */
    poURL = [NSURL fileURLWithPath:poName];

    /* Opens file */
    if(ExtAudioFileOpenURL((CFURLRef)poURL, &(_pstData->extaudio.oFileRef)) == 0)
    {
      AudioStreamBasicDescription stFileInfo;
      UInt32                      u32InfoSize;

      /* Gets file info size  */
      u32InfoSize = sizeof(AudioStreamBasicDescription);

      /* Clears file info */
      orxMemory_Zero(&stFileInfo, u32InfoSize);

      /* Gets file info */
      if(ExtAudioFileGetProperty(_pstData->extaudio.oFileRef, kExtAudioFileProperty_FileDataFormat, &u32InfoSize, &stFileInfo) == 0)
      {
        /* Valid number of channels */
        if(stFileInfo.mChannelsPerFrame <= 2)
        {
          /* Updates file info for 16bit PCM data */
          stFileInfo.mFormatID        = kAudioFormatLinearPCM;
          stFileInfo.mBytesPerPacket  = 2 * stFileInfo.mChannelsPerFrame;
          stFileInfo.mFramesPerPacket = 1;
          stFileInfo.mBytesPerFrame   = 2 * stFileInfo.mChannelsPerFrame;
          stFileInfo.mBitsPerChannel  = 16;
          stFileInfo.mFormatFlags     = kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked | kAudioFormatFlagIsSignedInteger;

          /* Applies it */
          if(ExtAudioFileSetProperty(_pstData->extaudio.oFileRef, kExtAudioFileProperty_ClientDataFormat, u32InfoSize, &stFileInfo) == 0)
          {
            SInt64 s64FrameNumber;

            /* Gets frame number size */
            u32InfoSize = sizeof(SInt64);

            /* Get the frame number */
            if(ExtAudioFileGetProperty(_pstData->extaudio.oFileRef, kExtAudioFileProperty_FileLengthFrames, &u32InfoSize, &s64FrameNumber) == 0)
            {
              /* Stores info */
              _pstData->stInfo.u32ChannelNumber = (orxU32)stFileInfo.mChannelsPerFrame;
              _pstData->stInfo.u32FrameNumber   = (orxU32)s64FrameNumber;
              _pstData->stInfo.u32SampleRate    = (orxU32)stFileInfo.mSampleRate;

              /* Updates status */
              _pstData->bVorbis                 = orxFALSE;

              /* Updates result */
              eResult = orxSTATUS_SUCCESS;
            }
            else
            {
              /* Logs message */
              orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: can't get file size.", _zFilename);
            }
          }
          else
          {
            /* Logs message */
            orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: can't convert to 16bit PCM.", _zFilename);
          }
        }
        else
        {
          /* Logs message */
          orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: too many channels.", _zFilename);
        }
      }
      else
      {
        /* Logs message */
        orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: invalid format.", _zFilename);
      }
    }
    else
    {
      /* Logs message */
      orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: can't find/load the file.", _zFilename);
    }
  }

  /* Done! */
  return eResult;
}

static orxINLINE void orxSoundSystem_iOS_CloseFile(orxSOUNDSYSTEM_DATA *_pstData)
{
  /* Checks */
  orxASSERT(_pstData != orxNULL);

  /* vorbis? */
  if(_pstData->bVorbis != orxFALSE)
  {
    /* Has valid file? */
    if(_pstData->vorbis.pstFile != orxNULL)
    {
      /* Closes file */
      stb_vorbis_close(_pstData->vorbis.pstFile);
      _pstData->vorbis.pstFile = orxNULL;

      /* Closes resource */
      orxResource_Close(_pstData->vorbis.hResource);
      _pstData->vorbis.hResource = orxNULL;
    }
  }
  /* extaudio */
  else
  {
    /* Has file? */
    if(_pstData->extaudio.oFileRef != orxNULL)
    {
      /* Dispose audio file */
      ExtAudioFileDispose(_pstData->extaudio.oFileRef);
      _pstData->extaudio.oFileRef = orxNULL;
    }
  }

  /* Done! */
  return;
}

static orxINLINE orxU32 orxSoundSystem_iOS_Read(orxSOUNDSYSTEM_DATA *_pstData, orxU32 _u32FrameNumber, void *_pBuffer)
{
  orxU32 u32Result;

  /* Checks */
  orxASSERT(_pstData != orxNULL);

  /* vorbis? */
  if(_pstData->bVorbis != orxFALSE)
  {
    /* Has valid file? */
    if(_pstData->vorbis.pstFile != orxNULL)
    {
      /* Reads frames */
      u32Result = (orxU32)stb_vorbis_get_samples_short_interleaved(_pstData->vorbis.pstFile, (int)_pstData->stInfo.u32ChannelNumber, (short *)_pBuffer, (int)(_u32FrameNumber * _pstData->stInfo.u32ChannelNumber));
    }
    else
    {
      /* Clears buffer */
      orxMemory_Zero(_pBuffer, _u32FrameNumber * _pstData->stInfo.u32ChannelNumber * sizeof(orxS16));

      /* Updates result */
      u32Result = _u32FrameNumber;
    }
  }
  /* extaudio */
  else
  {
    /* Has valid file? */
    if(_pstData->extaudio.oFileRef != orxNULL)
    {
      AudioBufferList stBufferInfo;
      UInt32          u32BufferSize;

      /* Inits frame number */
      u32Result = _u32FrameNumber;

      /* Gets buffer size */
      u32BufferSize = _u32FrameNumber * 2 * _pstData->stInfo.u32ChannelNumber;

      /* Inits buffer info */
      stBufferInfo.mNumberBuffers               = 1;
      stBufferInfo.mBuffers[0].mDataByteSize    = u32BufferSize;
      stBufferInfo.mBuffers[0].mNumberChannels  = _pstData->stInfo.u32ChannelNumber;
      stBufferInfo.mBuffers[0].mData            = _pBuffer;

      /* Reads frames */
      ExtAudioFileRead(_pstData->extaudio.oFileRef, (UInt32 *)&u32Result, &stBufferInfo);
    }
    else
    {
      /* Clears buffer */
      orxMemory_Zero(_pBuffer, _u32FrameNumber * _pstData->stInfo.u32ChannelNumber * sizeof(orxS16));

      /* Updates result */
      u32Result = _u32FrameNumber;
    }
  }

  /* Done! */
  return u32Result;
}

static orxINLINE void orxSoundSystem_iOS_Rewind(orxSOUNDSYSTEM_DATA *_pstData)
{
  /* Checks */
  orxASSERT(_pstData != orxNULL);

  /* vorbis? */
  if(_pstData->bVorbis != orxFALSE)
  {
    /* Has valid file? */
    if(_pstData->vorbis.pstFile != orxNULL)
    {
      /* Seeks start */
      stb_vorbis_seek_start(_pstData->vorbis.pstFile);
    }
  }
  /* extaudio */
  else
  {
    /* Has valid file? */
    if(_pstData->extaudio.oFileRef != orxNULL)
    {
      /* Seeks start */
      ExtAudioFileSeek(_pstData->extaudio.oFileRef, 0);
    }
  }

  /* Done! */
  return;
}

static void orxFASTCALL orxSoundSystem_iOS_FillStream(orxSOUNDSYSTEM_SOUND *_pstSound)
{
  /* Checks */
  orxASSERT(_pstSound != orxNULL);

  /* Not stopped? */
  if(_pstSound->bStop == orxFALSE)
  {
    ALint   iBufferNumber = 0;
    ALuint *puiBufferList;

    /* Gets number of queued buffers */
    alGetSourcei(_pstSound->uiSource, AL_BUFFERS_QUEUED, &iBufferNumber);
    alASSERT();

    /* None found? */
    if(iBufferNumber == 0)
    {
      /* Uses initial buffer list */
      puiBufferList = _pstSound->auiBufferList;

      /* Updates buffer number */
      iBufferNumber = sstSoundSystem.s32StreamBufferNumber;
    }
    else
    {
      /* Gets number of processed buffers */
      iBufferNumber = 0;
      alGetSourcei(_pstSound->uiSource, AL_BUFFERS_PROCESSED, &iBufferNumber);
      alASSERT();

      /* Found any? */
      if(iBufferNumber > 0)
      {
        /* Uses local list */
        puiBufferList = sstSoundSystem.auiWorkBufferList;

        /* Unqueues them all */
        alSourceUnqueueBuffers(_pstSound->uiSource, orxMIN(iBufferNumber, sstSoundSystem.s32StreamBufferNumber), puiBufferList);
        alASSERT();
      }
    }

    /* Needs processing? */
    if(iBufferNumber > 0)
    {
      orxU32                 u32BufferFrameNumber, u32FrameNumber, i;
      orxSOUND_EVENT_PAYLOAD stPayload;

      /* Clears payload */
      orxMemory_Zero(&stPayload, sizeof(orxSOUND_EVENT_PAYLOAD));

      /* Stores recording name */
      stPayload.zSoundName = _pstSound->zReference;

      /* Stores stream info */
      stPayload.stStream.stInfo.u32SampleRate     = _pstSound->stData.stInfo.u32SampleRate;
      stPayload.stStream.stInfo.u32ChannelNumber  = _pstSound->stData.stInfo.u32ChannelNumber;

      /* Stores time stamp */
      stPayload.stStream.stPacket.fTimeStamp = (orxFLOAT)orxSystem_GetTime();

      /* Gets buffer's frame number */
      u32BufferFrameNumber = sstSoundSystem.s32StreamBufferSize / _pstSound->stData.stInfo.u32ChannelNumber;

      /* For all processed buffers */
      for(i = 0, u32FrameNumber = u32BufferFrameNumber; i < (orxU32)iBufferNumber; i++)
      {
        orxBOOL bEOF = orxFALSE;

        /* Fills buffer */
        u32FrameNumber = orxSoundSystem_iOS_Read(&(_pstSound->stData), u32BufferFrameNumber, sstSoundSystem.as16StreamBuffer);

        /* Inits packet */
        stPayload.stStream.stPacket.u32SampleNumber = u32FrameNumber * _pstSound->stData.stInfo.u32ChannelNumber;
        stPayload.stStream.stPacket.as16SampleList  = sstSoundSystem.as16StreamBuffer;
        stPayload.stStream.stPacket.bDiscard        = orxFALSE;
        stPayload.stStream.stPacket.s32ID           = _pstSound->s32PacketID++;

        /* Sends event */
        orxEVENT_SEND(orxEVENT_TYPE_SOUND, orxSOUND_EVENT_PACKET, orxNULL, orxNULL, &stPayload);

        /* Should proceed? */
        if(stPayload.stStream.stPacket.bDiscard == orxFALSE)
        {
          /* Success? */
          if(u32FrameNumber > 0)
          {
            /* Transfers its data */
            alBufferData(puiBufferList[i], (_pstSound->stData.stInfo.u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, stPayload.stStream.stPacket.as16SampleList, (ALsizei)(stPayload.stStream.stPacket.u32SampleNumber * sizeof(orxS16)), (ALsizei)_pstSound->stData.stInfo.u32SampleRate);
            alASSERT();

            /* Queues it */
            alSourceQueueBuffers(_pstSound->uiSource, 1, &puiBufferList[i]);
            alASSERT();

            /* End of file? */
            if(u32FrameNumber < u32BufferFrameNumber)
            {
              /* Updates status */
              bEOF = orxTRUE;
            }
          }
          else
          {
            /* Clears its data */
            alBufferData(puiBufferList[i], (_pstSound->stData.stInfo.u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, stPayload.stStream.stPacket.as16SampleList, 0, (ALsizei)_pstSound->stData.stInfo.u32SampleRate);
            alASSERT();

            /* Queues it */
            alSourceQueueBuffers(_pstSound->uiSource, 1, &puiBufferList[i]);
            alASSERT();

            /* Updates status */
            bEOF = orxTRUE;
          }

          /* Ends of file? */
          if(bEOF != orxFALSE)
          {
            /* Rewinds file */
            orxSoundSystem_iOS_Rewind(&(_pstSound->stData));

            /* Not looping? */
            if(_pstSound->bLoop == orxFALSE)
            {
              /* Stops */
              _pstSound->bStop = orxTRUE;
              break;
            }
          }
        }
        else
        {
          /* Clears its data */
          alBufferData(puiBufferList[i], (_pstSound->stData.stInfo.u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, stPayload.stStream.stPacket.as16SampleList, 0, (ALsizei)_pstSound->stData.stInfo.u32SampleRate);
          alASSERT();

          /* Queues it */
          alSourceQueueBuffers(_pstSound->uiSource, 1, &puiBufferList[i]);
          alASSERT();
        }
      }
    }

    /* Should continue */
    if(_pstSound->bStop == orxFALSE)
    {
      ALint iState;

      /* Gets actual state */
      alGetSourcei(_pstSound->uiSource, AL_SOURCE_STATE, &iState);
      alASSERT();

      /* Stopped? */
      if((iState == AL_STOPPED) || (iState == AL_INITIAL))
      {
        /* Resumes play */
        alSourcePlay(_pstSound->uiSource);
        alASSERT();
      }
    }
  }
  else
  {
    ALint iState;

    /* Gets actual state */
    alGetSourcei(_pstSound->uiSource, AL_SOURCE_STATE, &iState);
    alASSERT();

    /* Stopped? */
    if((iState == AL_STOPPED) || (iState == AL_INITIAL))
    {
      ALint iQueuedBufferNumber = 0, iProcessedBufferNumber;

      /* Gets queued & processed buffer numbers */
      alGetSourcei(_pstSound->uiSource, AL_BUFFERS_QUEUED, &iQueuedBufferNumber);
      alASSERT();
      alGetSourcei(_pstSound->uiSource, AL_BUFFERS_PROCESSED, &iProcessedBufferNumber);
      alASSERT();

      /* Checks */
      orxASSERT(iProcessedBufferNumber <= iQueuedBufferNumber);
      orxASSERT(iQueuedBufferNumber <= sstSoundSystem.s32StreamBufferNumber);

      /* Found any? */
      if(iQueuedBufferNumber > 0)
      {
        /* Updates sound packet ID */
        _pstSound->s32PacketID -= (orxS32)(iQueuedBufferNumber - iProcessedBufferNumber);

        /* Unqueues them */
        alSourceUnqueueBuffers(_pstSound->uiSource, orxMIN(iQueuedBufferNumber, sstSoundSystem.s32StreamBufferNumber), sstSoundSystem.auiWorkBufferList);
        alASSERT();
      }
    }
  }

  /* Done! */
  return;
}

static void orxFASTCALL orxSoundSystem_iOS_UpdateRecording()
{
  ALCint iSampleNumber;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(orxFLAG_TEST(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING));

  /* Gets the number of captured samples */
  alcGetIntegerv(sstSoundSystem.poCaptureDevice, ALC_CAPTURE_SAMPLES, 1, &iSampleNumber);

  /* For all packets */
  while(iSampleNumber > 0)
  {
    orxU32 u32PacketSampleNumber;

    /* Gets sample number for this packet */
    u32PacketSampleNumber = (orxU32)orxMIN(iSampleNumber, sstSoundSystem.s32StreamBufferSize);

    /* Inits packet */
    sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber  = u32PacketSampleNumber;
    sstSoundSystem.stRecordingPayload.stStream.stPacket.as16SampleList   = sstSoundSystem.as16RecordingBuffer;

    /* Gets the captured samples */
    alcCaptureSamples(sstSoundSystem.poCaptureDevice, (ALCvoid *)sstSoundSystem.as16RecordingBuffer, (ALCsizei)sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber);

    /* Sends event */
    orxEVENT_SEND(orxEVENT_TYPE_SOUND, orxSOUND_EVENT_RECORDING_PACKET, orxNULL, orxNULL, &(sstSoundSystem.stRecordingPayload));

    /* Should write the packet? */
    if(sstSoundSystem.stRecordingPayload.stStream.stPacket.bDiscard == orxFALSE)
    {
      /* No file opened yet? */
      if(sstSoundSystem.poRecordingFile == orxNULL)
      {
        /* Opens it */
        orxSoundSystem_iOS_OpenRecordingFile();
      }

      /* Has a valid file opened? */
      if(sstSoundSystem.poRecordingFile != orxNULL)
      {
        AudioBufferList stBufferInfo;

        /* Inits buffer info */
        stBufferInfo.mNumberBuffers               = 1;
        stBufferInfo.mBuffers[0].mDataByteSize    = sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber * sizeof(orxS16);
        stBufferInfo.mBuffers[0].mNumberChannels  = sstSoundSystem.stRecordingPayload.stStream.stInfo.u32ChannelNumber;
        stBufferInfo.mBuffers[0].mData            = sstSoundSystem.stRecordingPayload.stStream.stPacket.as16SampleList;

        /* Writes data */
        ExtAudioFileWrite(sstSoundSystem.poRecordingFile, sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber / sstSoundSystem.stRecordingPayload.stStream.stInfo.u32ChannelNumber, &stBufferInfo);
      }
    }

    /* Updates remaining sample number */
    iSampleNumber -= (ALCint)u32PacketSampleNumber;

    /* Updates timestamp */
    sstSoundSystem.stRecordingPayload.stStream.stPacket.fTimeStamp += orxU2F(sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber) / orxU2F(sstSoundSystem.stRecordingPayload.stStream.stInfo.u32SampleRate * sstSoundSystem.stRecordingPayload.stStream.stInfo.u32ChannelNumber);
  }

  /* Updates packet's timestamp */
  sstSoundSystem.stRecordingPayload.stStream.stPacket.fTimeStamp = (orxFLOAT)orxSystem_GetTime();

  /* Done! */
  return;
}

static void orxFASTCALL orxSoundSystem_iOS_UpdateStreaming(const orxCLOCK_INFO *_pstInfo, void *_pContext)
{
  orxLINKLIST_NODE *pstNode;

  /* Profiles */
  orxPROFILER_PUSH_MARKER("orxSoundSystem_UpdateStreaming");

  /* Is recording? */
  if(orxFLAG_TEST(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING))
  {
    /* Updates recording */
    orxSoundSystem_iOS_UpdateRecording();
  }

  /* For all streams nodes */
  for(pstNode = orxLinkList_GetFirst(&(sstSoundSystem.stStreamList));
      pstNode != orxNULL;
      pstNode = orxLinkList_GetNext(pstNode))
  {
    orxSOUNDSYSTEM_SOUND *pstSound;

    /* Gets associated sound */
    pstSound = (orxSOUNDSYSTEM_SOUND *)((orxU8 *)pstNode - (orxU8 *)&(((orxSOUNDSYSTEM_SOUND *)0)->stNode));

    /* Fills its stream */
    orxSoundSystem_iOS_FillStream(pstSound);
  }

  /* Profiles */
  orxPROFILER_POP_MARKER();
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Init()
{
  orxSTATUS eResult = orxSTATUS_FAILURE;

  /* Was already initialized? */
  if(!(sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY))
  {
    /* Cleans static controller */
    orxMemory_Zero(&sstSoundSystem, sizeof(orxSOUNDSYSTEM_STATIC));

    /* Pushes config section */
    orxConfig_PushSection(orxSOUNDSYSTEM_KZ_CONFIG_SECTION);

    /* Opens device */
    sstSoundSystem.poDevice = alcOpenDevice(NULL);

    /* Valid? */
    if(sstSoundSystem.poDevice != NULL)
    {
      /* Creates associated context */
      sstSoundSystem.poContext = alcCreateContext(sstSoundSystem.poDevice, NULL);

      /* Has stream buffer size? */
      if(orxConfig_HasValue(orxSOUNDSYSTEM_KZ_CONFIG_STREAM_BUFFER_SIZE) != orxFALSE)
      {
        /* Stores it */
        sstSoundSystem.s32StreamBufferSize = orxConfig_GetU32(orxSOUNDSYSTEM_KZ_CONFIG_STREAM_BUFFER_SIZE) & 0xFFFFFFFC;
      }
      else
      {
        /* Uses default one */
        sstSoundSystem.s32StreamBufferSize = orxSOUNDSYSTEM_KS32_DEFAULT_STREAM_BUFFER_SIZE;
      }

      /* Has stream buffer number? */
      if(orxConfig_HasValue(orxSOUNDSYSTEM_KZ_CONFIG_STREAM_BUFFER_NUMBER) != orxFALSE)
      {
        /* Gets stream number */
        sstSoundSystem.s32StreamBufferNumber = orxMAX(2, orxConfig_GetU32(orxSOUNDSYSTEM_KZ_CONFIG_STREAM_BUFFER_NUMBER));
      }
      else
      {
        /* Uses default ont */
        sstSoundSystem.s32StreamBufferNumber = orxSOUNDSYSTEM_KS32_DEFAULT_STREAM_BUFFER_NUMBER;
      }

      /* Valid? */
      if(sstSoundSystem.poContext != NULL)
      {
        /* Creates banks */
        sstSoundSystem.pstSampleBank  = orxBank_Create(orxSOUNDSYSTEM_KU32_BANK_SIZE, sizeof(orxSOUNDSYSTEM_SAMPLE), orxBANK_KU32_FLAG_NONE, orxMEMORY_TYPE_MAIN);
        sstSoundSystem.pstSoundBank   = orxBank_Create(orxSOUNDSYSTEM_KU32_BANK_SIZE, sizeof(orxSOUNDSYSTEM_SOUND) + sstSoundSystem.s32StreamBufferNumber * sizeof(ALuint), orxBANK_KU32_FLAG_NONE, orxMEMORY_TYPE_MAIN);

        /* Valid? */
        if((sstSoundSystem.pstSampleBank != orxNULL) && (sstSoundSystem.pstSoundBank))
        {
          /* Adds streaming timer */
          if(orxClock_Register(orxClock_FindFirst(orx2F(-1.0f), orxCLOCK_TYPE_CORE), orxSoundSystem_iOS_UpdateStreaming, orxNULL, orxMODULE_ID_SOUNDSYSTEM, orxCLOCK_PRIORITY_LOW) != orxSTATUS_FAILURE)
          {
            ALfloat   afOrientation[] = {0.0f, 0.0f, -1.0f, 0.0f, 1.0f, 0.0f};
            orxFLOAT  fRatio;

            /* Selects it */
            alcMakeContextCurrent(sstSoundSystem.poContext);

            /* Sets 2D listener target */
            alListenerfv(AL_ORIENTATION, afOrientation);
            alASSERT();

            /* Allocates stream buffers */
            sstSoundSystem.as16StreamBuffer     = (orxS16 *)orxMemory_Allocate(sstSoundSystem.s32StreamBufferSize * sizeof(orxS16), orxMEMORY_TYPE_AUDIO);
            sstSoundSystem.as16RecordingBuffer  = (orxS16 *)orxMemory_Allocate(sstSoundSystem.s32StreamBufferSize * sizeof(orxS16), orxMEMORY_TYPE_AUDIO);

            /* Allocates working buffer list */
            sstSoundSystem.auiWorkBufferList    = (ALuint *)orxMemory_Allocate(sstSoundSystem.s32StreamBufferNumber * sizeof(ALuint), orxMEMORY_TYPE_AUDIO);

            /* Gets dimension ratio */
            fRatio = orxConfig_GetFloat(orxSOUNDSYSTEM_KZ_CONFIG_RATIO);

            /* Valid? */
            if(fRatio > orxFLOAT_0)
            {
              /* Stores it */
              sstSoundSystem.fDimensionRatio = fRatio;
            }
            else
            {
              /* Stores default one */
              sstSoundSystem.fDimensionRatio = orxSOUNDSYSTEM_KF_DEFAULT_DIMENSION_RATIO;
            }

            /* Stores reciprocal dimenstion ratio */
            sstSoundSystem.fRecDimensionRatio = orxFLOAT_1 / sstSoundSystem.fDimensionRatio;

            /* Updates status */
            orxFLAG_SET(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY, orxSOUNDSYSTEM_KU32_STATIC_MASK_ALL);

            /* Updates result */
            eResult = orxSTATUS_SUCCESS;
          }
          else
          {
            /* Deletes banks */
            if(sstSoundSystem.pstSampleBank != orxNULL)
            {
              orxBank_Delete(sstSoundSystem.pstSampleBank);
              sstSoundSystem.pstSampleBank = orxNULL;
            }
            if(sstSoundSystem.pstSoundBank != orxNULL)
            {
              orxBank_Delete(sstSoundSystem.pstSoundBank);
              sstSoundSystem.pstSoundBank = orxNULL;
            }

            /* Destroys openAL context */
            alcDestroyContext(sstSoundSystem.poContext);
            sstSoundSystem.poContext = NULL;

            /* Closes openAL device */
            alcCloseDevice(sstSoundSystem.poDevice);
            sstSoundSystem.poDevice = NULL;
          }
        }
        else
        {
          /* Deletes banks */
          if(sstSoundSystem.pstSampleBank != orxNULL)
          {
            orxBank_Delete(sstSoundSystem.pstSampleBank);
            sstSoundSystem.pstSampleBank = orxNULL;
          }
          if(sstSoundSystem.pstSoundBank != orxNULL)
          {
            orxBank_Delete(sstSoundSystem.pstSoundBank);
            sstSoundSystem.pstSoundBank = orxNULL;
          }

          /* Destroys openAL context */
          alcDestroyContext(sstSoundSystem.poContext);
          sstSoundSystem.poContext = NULL;

          /* Closes openAL device */
          alcCloseDevice(sstSoundSystem.poDevice);
          sstSoundSystem.poDevice = NULL;
        }
      }
      else
      {
        /* Closes openAL device */
        alcCloseDevice(sstSoundSystem.poDevice);
        sstSoundSystem.poDevice = NULL;
      }
    }

    /* Pops config section */
    orxConfig_PopSection();
  }

  /* Done! */
  return eResult;
}

void orxFASTCALL orxSoundSystem_iOS_Exit()
{
  /* Was initialized? */
  if(sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY)
  {
    /* Unregisters fill stream callback */
    orxClock_Unregister(orxClock_FindFirst(orx2F(-1.0f), orxCLOCK_TYPE_CORE), orxSoundSystem_iOS_UpdateStreaming);

    /* Deletes working buffer list */
    orxMemory_Free(sstSoundSystem.auiWorkBufferList);

    /* Deletes stream buffers */
    orxMemory_Free(sstSoundSystem.as16StreamBuffer);
    orxMemory_Free(sstSoundSystem.as16RecordingBuffer);

    /* Deletes banks */
    orxBank_Delete(sstSoundSystem.pstSampleBank);
    orxBank_Delete(sstSoundSystem.pstSoundBank);

    /* Removes current context */
    alcMakeContextCurrent(NULL);

    /* Deletes context */
    alcDestroyContext(sstSoundSystem.poContext);

    /* Has capture device? */
    if(sstSoundSystem.poCaptureDevice != orxNULL)
    {
      /* Closes it */
      alcCaptureCloseDevice(sstSoundSystem.poCaptureDevice);
    }

    /* Closes device */
    alcCloseDevice(sstSoundSystem.poDevice);

    /* Cleans static controller */
    orxMemory_Zero(&sstSoundSystem, sizeof(orxSOUNDSYSTEM_STATIC));
  }

  return;
}

orxSOUNDSYSTEM_SAMPLE *orxFASTCALL orxSoundSystem_iOS_CreateSample(orxU32 _u32ChannelNumber, orxU32 _u32FrameNumber, orxU32 _u32SampleRate)
{
  orxSOUNDSYSTEM_SAMPLE *pstResult = NULL;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);

  /* Valid parameters? */
  if((_u32ChannelNumber >= 1) && (_u32ChannelNumber <= 2) && (_u32FrameNumber > 0) && (_u32SampleRate > 0))
  {
    /* Allocates sample */
    pstResult = (orxSOUNDSYSTEM_SAMPLE *)orxBank_Allocate(sstSoundSystem.pstSampleBank);

    /* Valid? */
    if(pstResult != orxNULL)
    {
      orxU32  u32BufferSize;
      void   *pBuffer;

      /* Gets buffer size */
      u32BufferSize = _u32FrameNumber * _u32ChannelNumber * sizeof(orxS16);

      /* Allocates buffer */
      if((pBuffer = orxMemory_Allocate(u32BufferSize, orxMEMORY_TYPE_MAIN)) != orxNULL)
      {
        /* Clears it */
        orxMemory_Zero(pBuffer, u32BufferSize);

        /* Generates an OpenAL buffer */
        alGenBuffers(1, &(pstResult->uiBuffer));
        alASSERT();

        /* Transfers the data */
        alBufferData(pstResult->uiBuffer, (_u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, pBuffer, (ALsizei)u32BufferSize, (ALsizei)_u32SampleRate);
        alASSERT();

        /* Stores info */
        pstResult->stInfo.u32ChannelNumber  = _u32ChannelNumber;
        pstResult->stInfo.u32FrameNumber    = _u32FrameNumber;
        pstResult->stInfo.u32SampleRate     = _u32SampleRate;

        /* Stores duration */
        pstResult->fDuration = orxU2F(_u32FrameNumber) / orx2F(_u32SampleRate);

        /* Frees buffer */
        orxMemory_Free(pBuffer);
      }
      else
      {
        /* Deletes sample */
        orxBank_Free(sstSoundSystem.pstSampleBank, pstResult);

        /* Updates result */
        pstResult = orxNULL;

        /* Logs message */
        orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't create sound sample: can't allocate memory for data.");
      }
    }
  }

  /* Done! */
  return pstResult;
}

orxSOUNDSYSTEM_SAMPLE *orxFASTCALL orxSoundSystem_iOS_LoadSample(const orxSTRING _zFilename)
{
  orxSOUNDSYSTEM_DATA     stData;
  orxSOUNDSYSTEM_SAMPLE  *pstResult = NULL;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_zFilename != orxNULL);

  /* Clears data */
  orxMemory_Zero(&stData, sizeof(orxSOUNDSYSTEM_DATA));

  /* Opens file */
  if(orxSoundSystem_iOS_OpenFile(_zFilename, &stData) != orxSTATUS_FAILURE)
  {
    /* Allocates sample */
    pstResult = (orxSOUNDSYSTEM_SAMPLE *)orxBank_Allocate(sstSoundSystem.pstSampleBank);

    /* Valid? */
    if(pstResult != orxNULL)
    {
      orxU32  u32BufferSize;
      void   *pBuffer;

      /* Gets buffer size */
      u32BufferSize = stData.stInfo.u32FrameNumber * stData.stInfo.u32ChannelNumber * sizeof(orxS16);

      /* Allocates buffer */
      if((pBuffer = orxMemory_Allocate(u32BufferSize, orxMEMORY_TYPE_MAIN)) != orxNULL)
      {
        orxU32 u32ReadFrameNumber;

        /* Reads data */
        u32ReadFrameNumber = orxSoundSystem_iOS_Read(&stData, stData.stInfo.u32FrameNumber, pBuffer);

        /* Success? */
        if(u32ReadFrameNumber == stData.stInfo.u32FrameNumber)
        {
          /* Generates an OpenAL buffer */
          alGenBuffers(1, &(pstResult->uiBuffer));
          alASSERT();

          /* Transfers the data */
          alBufferData(pstResult->uiBuffer, (stData.stInfo.u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, pBuffer, (ALsizei)u32BufferSize, (ALsizei)stData.stInfo.u32SampleRate);
          alASSERT();

          /* Stores info */
          orxMemory_Copy(&(pstResult->stInfo), &(stData.stInfo), sizeof(orxSOUNDSYSTEM_INFO));

          /* Stores duration */
          pstResult->fDuration = orxU2F(stData.stInfo.u32FrameNumber) / orx2F(stData.stInfo.u32SampleRate);
        }
        else
        {
          /* Deletes sample */
          orxBank_Free(sstSoundSystem.pstSampleBank, pstResult);

          /* Updates result */
          pstResult = orxNULL;

          /* Logs message */
          orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: can't read data from file.", _zFilename);
        }

        /* Frees buffer */
        orxMemory_Free(pBuffer);
      }
      else
      {
        /* Deletes sample */
        orxBank_Free(sstSoundSystem.pstSampleBank, pstResult);

        /* Updates result */
        pstResult = orxNULL;

        /* Logs message */
        orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound sample <%s>: can't allocate memory for data.", _zFilename);
      }
    }

    /* Closes file */
    orxSoundSystem_iOS_CloseFile(&stData);
  }

  /* Done! */
  return pstResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_DeleteSample(orxSOUNDSYSTEM_SAMPLE *_pstSample)
{
  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSample != orxNULL);

  /* Deletes openAL buffer */
  alDeleteBuffers(1, &(_pstSample->uiBuffer));
  alASSERT();

  /* Deletes sample */
  orxBank_Free(sstSoundSystem.pstSampleBank, _pstSample);

  /* Done! */
  return orxSTATUS_SUCCESS;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_GetSampleInfo(const orxSOUNDSYSTEM_SAMPLE *_pstSample, orxU32 *_pu32ChannelNumber, orxU32 *_pu32FrameNumber, orxU32 *_pu32SampleRate)
{
  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSample != orxNULL);
  orxASSERT(_pu32ChannelNumber != orxNULL);
  orxASSERT(_pu32FrameNumber != orxNULL);
  orxASSERT(_pu32SampleRate != orxNULL);

  /* Updates info */
  *_pu32ChannelNumber = _pstSample->stInfo.u32ChannelNumber;
  *_pu32FrameNumber   = _pstSample->stInfo.u32FrameNumber;
  *_pu32SampleRate    = _pstSample->stInfo.u32SampleRate;

  /* Done! */
  return orxSTATUS_SUCCESS;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetSampleData(orxSOUNDSYSTEM_SAMPLE *_pstSample, const orxS16 *_as16Data, orxU32 _u32SampleNumber)
{
  orxSTATUS eResult;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSample != orxNULL);
  orxASSERT(_as16Data != orxNULL);

  /* Valid size? */
  if(_u32SampleNumber == _pstSample->stInfo.u32ChannelNumber * _pstSample->stInfo.u32FrameNumber)
  {
    /* Transfers the data */
    alBufferData(_pstSample->uiBuffer, (_pstSample->stInfo.u32ChannelNumber > 1) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16, (const ALvoid *)_as16Data, (ALsizei)(_u32SampleNumber * sizeof(orxS16)), (ALsizei)_pstSample->stInfo.u32SampleRate);
    alASSERT();

    /* Updates result */
    eResult = orxSTATUS_SUCCESS;
  }
  else
  {
    /* Updates result */
    eResult = orxSTATUS_FAILURE;
  }

  /* Done! */
  return eResult;
}

orxSOUNDSYSTEM_SOUND *orxFASTCALL orxSoundSystem_iOS_CreateFromSample(const orxSOUNDSYSTEM_SAMPLE *_pstSample)
{
  orxSOUNDSYSTEM_SOUND *pstResult = orxNULL;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSample != orxNULL);

  /* Allocates sound */
  pstResult = (orxSOUNDSYSTEM_SOUND *)orxBank_Allocate(sstSoundSystem.pstSoundBank);

  /* Valid? */
  if(pstResult != orxNULL)
  {
    /* Creates source */
    alGenSources(1, &(pstResult->uiSource));
    alASSERT();

    /* Inits it */
    alSourcei(pstResult->uiSource, AL_BUFFER, _pstSample->uiBuffer);
    alASSERT();
    alSourcef(pstResult->uiSource, AL_PITCH, 1.0f);
    alASSERT();
    alSourcef(pstResult->uiSource, AL_GAIN, 1.0f);
    alASSERT();

    /* Links sample */
    pstResult->pstSample = (orxSOUNDSYSTEM_SAMPLE *)_pstSample;

    /* Updates duration */
    pstResult->fDuration = _pstSample->fDuration;

    /* Updates status */
    pstResult->bIsStream = orxFALSE;
  }
  else
  {
    /* Logs message */
    orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't allocate memory for creating sound.");
  }

  /* Done! */
  return pstResult;
}

orxSOUNDSYSTEM_SOUND *orxFASTCALL orxSoundSystem_iOS_CreateStream(orxU32 _u32ChannelNumber, orxU32 _u32SampleRate, const orxSTRING _zReference)
{
  orxSOUNDSYSTEM_SOUND *pstResult = orxNULL;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_zReference != orxNULL);

  /* Valid parameters? */
  if((_u32ChannelNumber >= 1) && (_u32ChannelNumber <= 2) && (_u32SampleRate > 0))
  {
    /* Allocates sound */
    pstResult = (orxSOUNDSYSTEM_SOUND *)orxBank_Allocate(sstSoundSystem.pstSoundBank);

    /* Valid? */
    if(pstResult != orxNULL)
    {
      /* Clears it */
      orxMemory_Zero(pstResult, sizeof(orxSOUNDSYSTEM_SOUND));

      /* Generates openAL source */
      alGenSources(1, &(pstResult->uiSource));
      alASSERT();

      /* Generates all openAL buffers */
      alGenBuffers(sstSoundSystem.s32StreamBufferNumber, pstResult->auiBufferList);
      alASSERT();

      /* Stores information */
      pstResult->stData.stInfo.u32ChannelNumber = _u32ChannelNumber;
      pstResult->stData.stInfo.u32FrameNumber   = sstSoundSystem.s32StreamBufferSize / _u32ChannelNumber;
      pstResult->stData.stInfo.u32SampleRate    = _u32SampleRate;

      /* Stores duration */
      pstResult->fDuration = orx2F(-1.0f);

      /* Updates status */
      pstResult->bIsStream  = orxTRUE;
      pstResult->bStop      = orxTRUE;
      pstResult->bPause     = orxFALSE;
      pstResult->zReference = _zReference;
      pstResult->s32PacketID= 0;

      /* Adds it to the list */
      orxLinkList_AddEnd(&(sstSoundSystem.stStreamList), &(pstResult->stNode));
    }
    else
    {
      /* Logs message */
      orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load create stream: can't allocate sound structure.");
    }
  }

  /* Done! */
  return pstResult;
}

orxSOUNDSYSTEM_SOUND *orxFASTCALL orxSoundSystem_iOS_CreateStreamFromFile(const orxSTRING _zFilename, const orxSTRING _zReference)
{
  orxSOUNDSYSTEM_SOUND *pstResult = orxNULL;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_zFilename != orxNULL);

  /* Allocates sound */
  pstResult = (orxSOUNDSYSTEM_SOUND *)orxBank_Allocate(sstSoundSystem.pstSoundBank);

  /* Valid? */
  if(pstResult != orxNULL)
  {
    /* Clears it */
    orxMemory_Zero(pstResult, sizeof(orxSOUNDSYSTEM_SOUND));

    /* Generates openAL source */
    alGenSources(1, &(pstResult->uiSource));
    alASSERT();

    /* Opens file */
    if(orxSoundSystem_iOS_OpenFile(_zFilename, &(pstResult->stData)) != orxSTATUS_FAILURE)
    {
      /* Generates all openAL buffers */
      alGenBuffers(sstSoundSystem.s32StreamBufferNumber, pstResult->auiBufferList);
      alASSERT();

      /* Stores duration */
      pstResult->fDuration = orxU2F(pstResult->stData.stInfo.u32FrameNumber) / orx2F(pstResult->stData.stInfo.u32SampleRate);

      /* Updates status */
      pstResult->bIsStream  = orxTRUE;
      pstResult->bStop      = orxTRUE;
      pstResult->bPause     = orxFALSE;
      pstResult->zReference = _zReference;
      pstResult->s32PacketID= 0;

      /* Adds it to the list */
      orxLinkList_AddEnd(&(sstSoundSystem.stStreamList), &(pstResult->stNode));
    }
    else
    {
      /* Deletes openAL source */
      alDeleteSources(1, &(pstResult->uiSource));
      alASSERT();

      /* Deletes sound */
      orxBank_Free(sstSoundSystem.pstSoundBank, pstResult);

      /* Updates result */
      pstResult = orxNULL;
    }
  }
  else
  {
    /* Logs message */
    orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't load sound stream <%s>: can't allocate sound structure.", _zFilename);
  }

  /* Done! */
  return pstResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Delete(orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Deletes source */
  alDeleteSources(1, &(_pstSound->uiSource));
  alASSERT();

  /* Stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Dispose audio file */
    orxSoundSystem_iOS_CloseFile(&(_pstSound->stData));

    /* Clears buffers */
    alDeleteBuffers(sstSoundSystem.s32StreamBufferNumber, _pstSound->auiBufferList);
    alASSERT();

    /* Removes it from list */
    orxLinkList_Remove(&(_pstSound->stNode));
  }

  /* Deletes sound */
  orxBank_Free(sstSoundSystem.pstSoundBank, _pstSound);

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Play(orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Is a stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Not already playing? */
    if(_pstSound->bStop != orxFALSE)
    {
      /* Updates status */
      _pstSound->bStop = orxFALSE;

      /* Fills stream */
      orxSoundSystem_iOS_FillStream(_pstSound);
    }

    /* Updates status */
    _pstSound->bPause = orxFALSE;
  }

  /* Plays source */
  alSourcePlay(_pstSound->uiSource);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Pause(orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Pauses source */
  alSourcePause(_pstSound->uiSource);
  alASSERT();

  /* Is a stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Updates status */
    _pstSound->bPause = orxTRUE;
  }

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Stop(orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Stops source */
  alSourceStop(_pstSound->uiSource);
  alASSERT();

  /* Is a stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Rewinds file */
    orxSoundSystem_iOS_Rewind(&(_pstSound->stData));

    /* Updates status */
    _pstSound->bStop  = orxTRUE;
    _pstSound->bPause = orxFALSE;

    /* Fills stream */
    orxSoundSystem_iOS_FillStream(_pstSound);
  }

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_StartRecording(const orxSTRING _zName, orxBOOL _bWriteToFile, orxU32 _u32SampleRate, orxU32 _u32ChannelNumber)
{
  ALCenum   eALFormat;
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_zName != orxNULL);

  /* Not already recording? */
  if(!orxFLAG_TEST(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING))
  {
    /* Clears recording payload */
    orxMemory_Zero(&(sstSoundSystem.stRecordingPayload), sizeof(orxSOUND_EVENT_PAYLOAD));

    /* Stores recording name */
    sstSoundSystem.stRecordingPayload.zSoundName = orxString_Duplicate(_zName);

    /* Stores stream info */
    sstSoundSystem.stRecordingPayload.stStream.stInfo.u32SampleRate    = (_u32SampleRate > 0) ? _u32SampleRate : orxSOUNDSYSTEM_KS32_DEFAULT_RECORDING_FREQUENCY;
    sstSoundSystem.stRecordingPayload.stStream.stInfo.u32ChannelNumber = (_u32ChannelNumber == 2) ? 2 : 1;

    /* Stores discard status */
    sstSoundSystem.stRecordingPayload.stStream.stPacket.bDiscard = (_bWriteToFile != orxFALSE) ? orxFALSE : orxTRUE;

    /* Updates format based on the number of desired channels */
    eALFormat = (_u32ChannelNumber == 2) ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16;

    /* Opens the default capture device */
    sstSoundSystem.poCaptureDevice = alcCaptureOpenDevice(NULL, (ALCuint)sstSoundSystem.stRecordingPayload.stStream.stInfo.u32SampleRate, eALFormat, (ALCsizei)sstSoundSystem.stRecordingPayload.stStream.stInfo.u32SampleRate);

    /* Success? */
    if(sstSoundSystem.poCaptureDevice != NULL)
    {
      /* Should record? */
      if(_bWriteToFile != orxFALSE)
      {
        /* Opens file for recording */
        eResult = orxSoundSystem_iOS_OpenRecordingFile();
      }

      /* Success? */
      if(eResult != orxSTATUS_FAILURE)
      {
        /* Starts capture device */
        alcCaptureStart(sstSoundSystem.poCaptureDevice);

        /* Updates packet's timestamp */
        sstSoundSystem.stRecordingPayload.stStream.stPacket.fTimeStamp = (orxFLOAT)orxSystem_GetTime();

        /* Updates status */
        orxFLAG_SET(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING, orxSOUNDSYSTEM_KU32_STATIC_FLAG_NONE);

        /* Sends event */
        orxEVENT_SEND(orxEVENT_TYPE_SOUND, orxSOUND_EVENT_RECORDING_START, orxNULL, orxNULL, &(sstSoundSystem.stRecordingPayload));
      }
      else
      {
        /* Logs message */
        orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't start recording <%s>: failed to open file, aborting.", _zName);

        /* Deletes capture device */
        alcCaptureCloseDevice(sstSoundSystem.poCaptureDevice);
        sstSoundSystem.poCaptureDevice = orxNULL;
      }
    }
    else
    {
      /* Logs message */
      orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't start recording of <%s>: failed to open sound capture device.", _zName);

      /* Updates result */
      eResult = orxSTATUS_FAILURE;
    }
  }
  else
  {
    /* Logs message */
    orxDEBUG_PRINT(orxDEBUG_LEVEL_SOUND, "Can't start recording <%s> as the recording of <%s> is still in progress.", _zName, sstSoundSystem.stRecordingPayload.zSoundName);

    /* Updates result */
    eResult = orxSTATUS_FAILURE;
  }

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_StopRecording()
{
  orxSTATUS eResult;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);

  /* Recording right now? */
  if(orxFLAG_TEST(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING))
  {
    /* Processes the remaining samples */
    orxSoundSystem_iOS_UpdateRecording();

    /* Has a recording file? */
    if(sstSoundSystem.poRecordingFile != orxNULL)
    {
      /* Closes it */
      ExtAudioFileDispose(sstSoundSystem.poRecordingFile);
      sstSoundSystem.poRecordingFile = orxNULL;
    }

    /* Reinits the packet */
    sstSoundSystem.stRecordingPayload.stStream.stPacket.u32SampleNumber  = 0;
    sstSoundSystem.stRecordingPayload.stStream.stPacket.as16SampleList   = sstSoundSystem.as16RecordingBuffer;

    /* Stops the capture device */
    alcCaptureStop(sstSoundSystem.poCaptureDevice);

    /* Closes it */
    alcCaptureCloseDevice(sstSoundSystem.poCaptureDevice);
    sstSoundSystem.poCaptureDevice = orxNULL;

    /* Updates status */
    orxFLAG_SET(sstSoundSystem.u32Flags, orxSOUNDSYSTEM_KU32_STATIC_FLAG_NONE, orxSOUNDSYSTEM_KU32_STATIC_FLAG_RECORDING);

    /* Sends event */
    orxEVENT_SEND(orxEVENT_TYPE_SOUND, orxSOUND_EVENT_RECORDING_STOP, orxNULL, orxNULL, &(sstSoundSystem.stRecordingPayload));

    /* Deletes name */
    orxString_Delete((orxSTRING)sstSoundSystem.stRecordingPayload.zSoundName);
    sstSoundSystem.stRecordingPayload.zSoundName = orxNULL;

    /* Updates result */
    eResult = orxSTATUS_SUCCESS;
  }
  else
  {
    /* Updates result */
    eResult = orxSTATUS_FAILURE;
  }

  /* Done! */
  return eResult;
}

orxBOOL orxFASTCALL orxSoundSystem_iOS_HasRecordingSupport()
{
	const ALCchar  *zDeviceNameList;
  orxBOOL         bResult;

  /* Checks */
	orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);

  /* Gets capture device name list */
  zDeviceNameList = alcGetString(NULL, ALC_CAPTURE_DEVICE_SPECIFIER);

  /* Updates result */
  bResult = (zDeviceNameList[0] != orxCHAR_NULL) ? orxTRUE : orxFALSE;

  /* Done! */
  return bResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetVolume(orxSOUNDSYSTEM_SOUND *_pstSound, orxFLOAT _fVolume)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Sets source's gain */
  alSourcef(_pstSound->uiSource, AL_GAIN, _fVolume);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetPitch(orxSOUNDSYSTEM_SOUND *_pstSound, orxFLOAT _fPitch)
{
  orxSTATUS eResult = orxSTATUS_FAILURE;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Sets source's pitch */
  alSourcef(_pstSound->uiSource, AL_PITCH, _fPitch);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetPosition(orxSOUNDSYSTEM_SOUND *_pstSound, const orxVECTOR *_pvPosition)
{
  orxSTATUS eResult = orxSTATUS_FAILURE;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);
  orxASSERT(_pvPosition != orxNULL);

  /* Sets source position */
  alSource3f(_pstSound->uiSource, AL_POSITION, sstSoundSystem.fDimensionRatio * _pvPosition->fX, sstSoundSystem.fDimensionRatio * _pvPosition->fY, sstSoundSystem.fDimensionRatio * _pvPosition->fZ);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetAttenuation(orxSOUNDSYSTEM_SOUND *_pstSound, orxFLOAT _fAttenuation)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Set source's roll off factor */
  alSourcef(_pstSound->uiSource, AL_ROLLOFF_FACTOR, sstSoundSystem.fDimensionRatio * _fAttenuation);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetReferenceDistance(orxSOUNDSYSTEM_SOUND *_pstSound, orxFLOAT _fDistance)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Sets source's reference distance */
  alSourcef(_pstSound->uiSource, AL_REFERENCE_DISTANCE, sstSoundSystem.fDimensionRatio * _fDistance);
  alASSERT();

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_Loop(orxSOUNDSYSTEM_SOUND *_pstSound, orxBOOL _bLoop)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Updates status */
    _pstSound->bLoop = _bLoop;
  }
  else
  {
    /* Updates source */
    alSourcei(_pstSound->uiSource, AL_LOOPING, (_bLoop != orxFALSE) ? AL_TRUE : AL_FALSE);
    alASSERT();
  }

  /* Done! */
  return eResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetVolume(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxFLOAT fResult = orxFLOAT_0;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Updates result */
  alGetSourcef(_pstSound->uiSource, AL_GAIN, &fResult);
  alASSERT();

  /* Done! */
  return fResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetPitch(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxFLOAT fResult = orxFLOAT_0;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Updates result */
  alGetSourcef(_pstSound->uiSource, AL_PITCH, &fResult);
  alASSERT();

  /* Done! */
  return fResult;
}

orxVECTOR *orxFASTCALL orxSoundSystem_iOS_GetPosition(const orxSOUNDSYSTEM_SOUND *_pstSound, orxVECTOR *_pvPosition)
{
  orxVECTOR *pvResult = _pvPosition;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);
  orxASSERT(_pvPosition != orxNULL);

  /* Gets source's position */
  alGetSource3f(_pstSound->uiSource, AL_POSITION, &(pvResult->fX), &(pvResult->fY), &(pvResult->fZ));
  alASSERT();

  /* Updates result */
  orxVector_Mulf(pvResult, pvResult, sstSoundSystem.fRecDimensionRatio);

  /* Done! */
  return pvResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetAttenuation(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxFLOAT fResult;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Get source's roll off factor */
  alGetSourcef(_pstSound->uiSource, AL_ROLLOFF_FACTOR, &fResult);
  alASSERT();

  /* Updates result */
  fResult *= sstSoundSystem.fRecDimensionRatio;

  /* Done! */
  return fResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetReferenceDistance(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxFLOAT fResult;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Gets source's reference distance */
  alGetSourcef(_pstSound->uiSource, AL_REFERENCE_DISTANCE, &fResult);
  alASSERT();

  /* Updates result */
  fResult *= sstSoundSystem.fRecDimensionRatio;

  /* Done! */
  return fResult;
}

orxBOOL orxFASTCALL orxSoundSystem_iOS_IsLooping(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  ALint   iLooping;
  orxBOOL bResult;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Stream? */
  if(_pstSound->bIsStream != orxFALSE)
  {
    /* Updates result */
    bResult = _pstSound->bLoop;
  }
  else
  {
    /* Gets looping property */
    alGetSourcei(_pstSound->uiSource, AL_LOOPING, &iLooping);
    alASSERT();

    /* Updates result */
    bResult = (iLooping == AL_FALSE) ? orxFALSE : orxTRUE;
  }

  /* Done! */
  return bResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetDuration(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  orxFLOAT fResult = orxFLOAT_0;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Updates result */
  fResult = _pstSound->fDuration;

  /* Done! */
  return fResult;
}

orxSOUNDSYSTEM_STATUS orxFASTCALL orxSoundSystem_iOS_GetStatus(const orxSOUNDSYSTEM_SOUND *_pstSound)
{
  ALint                 iState;
  orxSOUNDSYSTEM_STATUS eResult = orxSOUNDSYSTEM_STATUS_NONE;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pstSound != orxNULL);

  /* Gets source's state */
  alGetSourcei(_pstSound->uiSource, AL_SOURCE_STATE, &iState);
  alASSERT();

  /* Depending on it */
  switch(iState)
  {
    case AL_INITIAL:
    case AL_STOPPED:
    {
      /* Is stream? */
      if(_pstSound->bIsStream != orxFALSE)
      {
        /* Updates result */
        eResult = (_pstSound->bStop != orxFALSE) ? orxSOUNDSYSTEM_STATUS_STOP : (_pstSound->bPause != orxFALSE) ? orxSOUNDSYSTEM_STATUS_PAUSE : orxSOUNDSYSTEM_STATUS_PLAY;
      }
      else
      {
        /* Updates result */
        eResult = orxSOUNDSYSTEM_STATUS_STOP;
      }

      break;
    }

    case AL_PAUSED:
    {
      /* Updates result */
      eResult = orxSOUNDSYSTEM_STATUS_PAUSE;

      break;
    }

    case AL_PLAYING:
    {
      /* Updates result */
      eResult = orxSOUNDSYSTEM_STATUS_PLAY;

      break;
    }

    default:
    {
      break;
    }
  }

  /* Done! */
  return eResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetGlobalVolume(orxFLOAT _fVolume)
{
  orxSTATUS eResult = orxSTATUS_FAILURE;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);

  /* Sets listener's gain */
  alListenerf(AL_GAIN, _fVolume);
  alASSERT();

  /* Done! */
  return eResult;
}

orxFLOAT orxFASTCALL orxSoundSystem_iOS_GetGlobalVolume()
{
  orxFLOAT fResult = orxFLOAT_0;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);

  /* Updates result */
  alGetListenerf(AL_GAIN, &fResult);
  alASSERT();

  /* Done! */
  return fResult;
}

orxSTATUS orxFASTCALL orxSoundSystem_iOS_SetListenerPosition(const orxVECTOR *_pvPosition)
{
  orxSTATUS eResult = orxSTATUS_SUCCESS;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pvPosition != orxNULL);

  /* Sets listener's position */
  alListener3f(AL_POSITION, sstSoundSystem.fDimensionRatio * _pvPosition->fX, sstSoundSystem.fDimensionRatio * _pvPosition->fY, sstSoundSystem.fDimensionRatio * _pvPosition->fZ);
  alASSERT();

  /* Done! */
  return eResult;
}

orxVECTOR *orxFASTCALL orxSoundSystem_iOS_GetListenerPosition(orxVECTOR *_pvPosition)
{
  orxVECTOR *pvResult = _pvPosition;

  /* Checks */
  orxASSERT((sstSoundSystem.u32Flags & orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY) == orxSOUNDSYSTEM_KU32_STATIC_FLAG_READY);
  orxASSERT(_pvPosition != orxNULL);

  /* Gets listener's position */
  alGetListener3f(AL_POSITION, &(pvResult->fX), &(pvResult->fY), &(pvResult->fZ));
  alASSERT();

  /* Updates result */
  orxVector_Mulf(pvResult, pvResult, sstSoundSystem.fRecDimensionRatio);

  /* Done! */
  return pvResult;
}


/***************************************************************************
 * Plugin related                                                          *
 ***************************************************************************/

orxPLUGIN_USER_CORE_FUNCTION_START(SOUNDSYSTEM);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Init, SOUNDSYSTEM, INIT);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Exit, SOUNDSYSTEM, EXIT);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_CreateSample, SOUNDSYSTEM, CREATE_SAMPLE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_LoadSample, SOUNDSYSTEM, LOAD_SAMPLE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_DeleteSample, SOUNDSYSTEM, DELETE_SAMPLE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetSampleInfo, SOUNDSYSTEM, GET_SAMPLE_INFO);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetSampleData, SOUNDSYSTEM, SET_SAMPLE_DATA);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_CreateFromSample, SOUNDSYSTEM, CREATE_FROM_SAMPLE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_CreateStream, SOUNDSYSTEM, CREATE_STREAM);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_CreateStreamFromFile, SOUNDSYSTEM, CREATE_STREAM_FROM_FILE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Delete, SOUNDSYSTEM, DELETE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Play, SOUNDSYSTEM, PLAY);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Pause, SOUNDSYSTEM, PAUSE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Stop, SOUNDSYSTEM, STOP);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_StartRecording, SOUNDSYSTEM, START_RECORDING);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_StopRecording, SOUNDSYSTEM, STOP_RECORDING);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_HasRecordingSupport, SOUNDSYSTEM, HAS_RECORDING_SUPPORT);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetVolume, SOUNDSYSTEM, SET_VOLUME);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetPitch, SOUNDSYSTEM, SET_PITCH);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetPosition, SOUNDSYSTEM, SET_POSITION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetAttenuation, SOUNDSYSTEM, SET_ATTENUATION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetReferenceDistance, SOUNDSYSTEM, SET_REFERENCE_DISTANCE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_Loop, SOUNDSYSTEM, LOOP);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetVolume, SOUNDSYSTEM, GET_VOLUME);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetPitch, SOUNDSYSTEM, GET_PITCH);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetPosition, SOUNDSYSTEM, GET_POSITION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetAttenuation, SOUNDSYSTEM, GET_ATTENUATION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetReferenceDistance, SOUNDSYSTEM, GET_REFERENCE_DISTANCE);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_IsLooping, SOUNDSYSTEM, IS_LOOPING);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetDuration, SOUNDSYSTEM, GET_DURATION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetStatus, SOUNDSYSTEM, GET_STATUS);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetGlobalVolume, SOUNDSYSTEM, SET_GLOBAL_VOLUME);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetGlobalVolume, SOUNDSYSTEM, GET_GLOBAL_VOLUME);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_SetListenerPosition, SOUNDSYSTEM, SET_LISTENER_POSITION);
orxPLUGIN_USER_CORE_FUNCTION_ADD(orxSoundSystem_iOS_GetListenerPosition, SOUNDSYSTEM, GET_LISTENER_POSITION);
orxPLUGIN_USER_CORE_FUNCTION_END();
