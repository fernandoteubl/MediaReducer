#!/bin/bash

# Text format
underline=`tput smul` ; nounderline=`tput rmul` ; bold=`tput bold` ; normal=`tput sgr0`

# Variables
imageTypes="jpg,jpeg,png,gif,heic"; imageTypes="$imageTypes,$(echo $imageTypes | tr '[a-z]' '[A-Z]')"
videoTypes="avi,mov,mp4"; videoTypes="$videoTypes,$(echo $videoTypes | tr '[a-z]' '[A-Z]')"
pathToFileOrDirectory=""
dirNameWithOriginalFiles="_original_files"
keepOriginalFiles=false
answerYesToAll=false
renameFiles=false
forceToRecreateFiles=false
maxPixelLargeSideFactor=3
resizeImage=false
resizeVideo=false
forceJPEG=false
jpegExtension="jpg"

setDefValues() {
	setDefValuesOpts="CQ, where C(odec) = m: h264, v: VP9, h: HVEC and Q(uality) = 1 (worse) to 5 (best) (eg.: m3, h4, v2)."
	case "${1:0:1}" in
	m) videoEncoder="h264_videotoolbox" ; audioEncoder="aac" ; videoExtensionOutput="mp4" ;;
	v) videoEncoder="libvpx-vp9"        ; audioEncoder="aac" ; videoExtensionOutput="mp4" ;;
	h) videoEncoder="hevc_videotoolbox" ; audioEncoder="aac" ; videoExtensionOutput="mp4" ;;
	*) echo "Invalid option. -p: ${setDefValuesOpts}" ; exit 1 ;;
	esac
	case "${1:1:1}" in
	1) imageMaxPixelSmallSide=640  ; imageQuality=60 ; videoMaxPixelSmallSide=480  ; videoKbps=760   ; audioKbps=64  ;  videoMaxFPS=24 ; videoCRF=24 ;;
	2) imageMaxPixelSmallSide=1280 ; imageQuality=70 ; videoMaxPixelSmallSide=720  ; videoKbps=2000  ; audioKbps=96  ;  videoMaxFPS=24 ; videoCRF=20 ;;
	3) imageMaxPixelSmallSide=1600 ; imageQuality=75 ; videoMaxPixelSmallSide=720  ; videoKbps=3000  ; audioKbps=128 ;  videoMaxFPS=30 ; videoCRF=18 ;;
	4) imageMaxPixelSmallSide=1920 ; imageQuality=80 ; videoMaxPixelSmallSide=1080 ; videoKbps=4000  ; audioKbps=196 ;  videoMaxFPS=30 ; videoCRF=16 ;;
	5) imageMaxPixelSmallSide=2560 ; imageQuality=85 ; videoMaxPixelSmallSide=1080 ; videoKbps=6000  ; audioKbps=384 ;  videoMaxFPS=60 ; videoCRF=12 ;;
	*) echo "Invalid option: -p : ${setDefValuesOpts}" ; exit 1 ;;
	esac
}
setDefValues m3


# Check commands...
warningCommand=false
errorCommand=false
# First all error, after all warning...
if [ ! -x "$(command -v exiv2)" ]; then
	echo "ERROR: exiv2 not found. Try install exiv2..."
	errorCommand=true
elif [ ! -x "$(command -v ffmpeg)" -o ! -x "$(command -v ffprobe)" ]; then
	echo "ERROR: ffmpeg not found."
	errorCommand=true
elif [[ ! $(ffmpeg -v quiet -codecs | grep ${videoEncoder}) ]]; then
	echo "Video encoder ${videoEncoder} not found."
	errorCommand=true
elif [ ! -x "$(command -v sips)" ]; then
	echo "WARNING: sips not found."
	warningCommand=true
fi
if [ $errorCommand = true ]; then
	echo -n "Press any key to abort..."
	read ans; exit 1
elif [ $warningCommand = true ]; then
	echo -n "Press 'y' to continue or any other key to cancel: "
	read ans; if [ "${ans}" != 'y' ]; then exit 1; fi
fi

# Options
usage(){
	echo "${bold}Usage:${normal} $0 [options] [<file_or_directory>][...]"
	echo "  <file_or_directory> Specific media file or a directory (and your subdirectories) with medias. If blank, list all medias in current directory."
	echo "  -r                  Rename all files with the creation date."
	echo "  -i [px]             Reduce the image size to MIN(W,H) <= px (if 0, uses default = ${imageMaxPixelSmallSide})."
	echo "  -q [qlty]           Set quality of image (0..100), used when it is resampled. (default = ${imageQuality})."
	echo "  -j                  Forcing ouput as JPEG format. (default = ${forceJPEG})"
	echo "  -v [px]             Reduce the video size to MIN(W,H) <= px (if 0, uses default = ${videoMaxPixelSmallSide})."
	echo "  -e [video_encode]   Set a video encoder. (default = ${videoEncoder})."
	echo "  -d [audio_encode]   Set a audio encoder. (default = ${audioEncoder})."
	echo "  -m [video_ext]      Set a video extension. (default = ${videoExtensionOutput})."
	echo "  -b [Kbps]           Set bitrate of video. (default = ${videoKbps})."
	echo "  -a [Kbps]           Set bitrate of audio. (default = ${audioKbps})."
	echo "  -f [FPS]            Set Max Frame Rate of video. It will never increase. (default = ${videoMaxFPS})."
	echo "  -c [CRF]            Set Constant Rate Factor of video. 0 is lossless, MAX is worst possible (MAX: x264=0-51 vpx 4-63). (default = ${videoCRF})."
	echo "  -l [fact]           Limit the image/video max side to MAX(W,H) <= px * fact (default = ${maxPixelLargeSideFactor})."
	echo "  -u                  Force to resample/encode all files. Also, if there is no date in the metadata, the file creation date will be used to rename it."
	echo "  -y                  Answer yes to all."
	echo "  -o                  Keep original files in a subfolder called \"${dirNameWithOriginalFiles}. (Just modified files)\""
	echo "  -p [def]            Predefined. ${setDefValuesOpts}"
}
checkIntegerValue() {
	if echo "$1" | egrep -q '^[0-9]+$'; then
		if [ $1 -lt $3 -o $1 -gt $4 ]; then
			echo "Please, the value of parameter \"-$2\" must be between $3 and $4."
			exit 1
		fi
	else
		echo "Please, parameter $2 must be a integer."
		exit 1
	fi
}
while getopts 'ri:q:jv:e:d:m:b:a:f:c:l:uyop:' args ; do
	case $args in
		r) renameFiles=true ;;
		i) resizeImage=true
			if [ "${OPTARG}" -gt 0 ]; then
				checkIntegerValue "${OPTARG}" "i" 160 6400
				imageMaxPixelSmallSide="${OPTARG}"
			fi ;;
		q) imageQuality="${OPTARG}"
			checkIntegerValue "${OPTARG}" "q" 0 100 ;;
		j) forceJPEG=true ;;
		v) resizeVideo=true
			if [ "${OPTARG}" -gt 0 ]; then
				checkIntegerValue "${OPTARG}" "v" 64 6400
				videoMaxPixelSmallSide="${OPTARG}"
			fi ;;
		e) videoEncoder="${OPTARG}"
			if [[ ! $(ffmpeg -v quiet -codecs | grep "${videoEncoder}") ]]; then echo "Video encoder ${OPTARG} not supported. (all availables: ffmpeg -v quiet -codecs)"; exit 1; fi ;;
		d) audioEncoder="${OPTARG}"
			if [[ ! $(ffmpeg -v quiet -codecs | grep "${audioEncoder}") ]]; then echo "Audio encoder ${OPTARG} not supported."; exit 1; fi ;;
		m) videoExtensionOutput="${OPTARG}"
			if [[ ! "${videoTypes}" =~ ${videoExtensionOutput} ]]; then echo "Video extension ${OPTARG} not supported."; exit 1; fi ;;
		b) videoKbps="${OPTARG}"
			checkIntegerValue "${OPTARG}" "b" 100 40000 ;;
		a) audioKbps="${OPTARG}"
			checkIntegerValue "${OPTARG}" "a" 48 1024 ;;
		f) videoMaxFPS="${OPTARG}"
			checkIntegerValue "${OPTARG}" "f" 1 960 ;;
		c) videoCRF="${OPTARG}"
			checkIntegerValue "${OPTARG}" "c" 0 64 ;;
		l) maxPixelLargeSideFactor="${OPTARG}"
			checkIntegerValue "${OPTARG}" "l" 1 10 ;;
		u) forceToRecreateFiles=true ;;
		y) answerYesToAll=true ;;
		o) keepOriginalFiles=true ;;
		p) resizeImage=true; resizeVideo=true
			setDefValues ${OPTARG} ;;
		*) usage ; exit 1 ;;
	esac
done

# Create array of files ...
declare -a listFiles
if [ "$#" -lt $OPTIND ]; then
	usage ; exit 1
else
	fileTypes="${imageTypes},${videoTypes}"
	regExFileTypes=".*\.(${fileTypes//,/|})$" # make regex to find files with extensions in $fileTypes
	shift $((OPTIND-1))
	for f in "$@"; do
		found=false
		if [ -d "${f}" ]; then
			while read -d "" filename; do # loop through all the image files
				if ! [ -z "${filename##*$dirNameWithOriginalFiles*}" ] ;then
					listFiles+=( "$filename" )
					found=true
				fi
			done < <(find -E "${f}" -iregex "$regExFileTypes" -print0)
		elif [ -f "${f}" ]; then
			if echo "${f}" | grep -Eq "$regExFileTypes"; then
				listFiles+=( "${f}" )
				found=true
			fi
		else
			if [ ${#listFiles[*]} -gt 0 ]; then echo ""; fi
			echo "Invalid input path: \"${f}\"."
			exit 1
		fi
		if [ $found = true ]; then
			echo -n -e "\r${#listFiles[*]} file(s) found with extension [${fileTypes}]."
		fi
	done
fi
if [ ${#listFiles[*]} -eq 0 ]; then
	echo "No files found with extension [${fileTypes}]."
	exit 1
else
	echo ""
	IFS=$'\n' listFiles=($(sort <<<"${listFiles[*]}" | uniq )); unset IFS # Sort list of files and remove all duplicated files !
fi



# Image functions
if [ -x "$(command -v sips)" ]; then
	imageTools="sips"
	getImageTimestamp(){
		# WARNING: sips shows other date (posible when is inserted the geo tag).
		# So, trying exiv before...
		RET=$(exiv2 "${1}" 2>/dev/null | grep timestamp )
		if [ $? = 0 ]; then
			echo ${RET//:/ } | sed "s/[^0-9 ]*//g" | sed -e 's/^ *//' -e 's/ *$//'
		else
			SIPS_RET=$(sips --getProperty creation "${1}" 2>/dev/null)
			if [ $? = 0 ]; then
				echo ${SIPS_RET} | sed -e 's/.* creation: //' | sed -e 's/:/ /g' | sed -e 's/<nil>//'
			fi
		fi
	}
	getImageSizeWH() {
		W=""; SIPS_RET=$(sips "$1" --getProperty pixelWidth 2>/dev/null)
		if [ $? = 0 ]; then  W=$(echo ${SIPS_RET} | sed -E "s/.*pixelWidth: ([0-9]+)/\1/g" | tail -1); fi
		H=""; SIPS_RET=$(sips "$1" --getProperty pixelHeight 2>/dev/null)
		if [ $? = 0 ]; then H=$(echo ${SIPS_RET} | sed  -E "s/.*pixelHeight: ([0-9]+)/\1/g" | tail -1); fi
		if [ "${W}" != "" -a "${H}" != "" ]; then  echo $W $H;  else echo ""; fi
	}
	resampleImageWH() {
		if [ $forceJPEG = true ]; then
			sips --setProperty formatOptions ${imageQuality} --setProperty format jpeg --resampleHeightWidth ${3} ${2} "${1}" -o "$4" >/dev/null
		else
			sips --setProperty formatOptions ${imageQuality} --resampleHeightWidth ${3} ${2} "${1}" -o "$4" >/dev/null
		fi
		return $?
	}
elif [ $forceJPEG = false -a -x "$(command -v exiv2)" -a -x "$(command -v convert)" ]; then
	imageTools="convert and exiv2"
	getImageTimestamp(){
		RET=$(exiv2 "${1}" 2>/dev/null | grep timestamp )
		if [ $? = 0 ]; then
			echo ${RET//:/ } | sed "s/[^0-9 ]*//g" | sed -e 's/^ *//' -e 's/ *$//'
		fi
	}
	getImageSizeWH() {
		RET=$( exiv2 "${1}" 2>/dev/null | grep Resolution )
		if [ $? = 0 ]; then
			echo $RET | sed -E "s/.*: //" | sed -E "s/ x / /g"
		fi
	}
	resampleImageWH() {
		convert "${1}" -resize "${2}x${3}" -quality ${imageQuality} "${4}"
		return $?
	}
else
	echo "ERROR: There is no image tools."
	exit -1
fi



# Video functions
videoTools="ffmpeg"
getVideoTimestamp(){
	QUICKTIME_CREATIONDATE=$( ffmpeg -i "$1" 2>&1 | grep com.apple.quicktime.creationdate | head -n 1 | sed -e 's/[^0-9]/ /g'  | awk '{  print $1 " " $2 " " $3 " " $4 " " $5 " " $6 }' OFS=' ' )
	if [[ $QUICKTIME_CREATIONDATE != "" ]]; then
		echo $QUICKTIME_CREATIONDATE
	else
		echo $( ffmpeg -i "$1" 2>&1 | grep creation_time | head -n 1 | sed -e 's/[^0-9]/ /g'  | awk '{  print $1 " " $2 " " $3 " " $4 " " $5 " " $6 }' OFS=' ' )
	fi
}
getVideoSizeWHF(){
	read w h <<< $( ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of default=nw=1:nk=1 "${1}" )
	f=$( ffmpeg -i "${1}" 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p" )
	rot=$( ffmpeg -i "$1"  2>&1 | grep rotate | head -n 1 | sed -e 's/[^0-9]/ /g' | awk '{ print $1 }' )
	if [ -z "$rot" ] || [ $rot -eq 180 ]; then
		echo $w $h $f
	else
		echo $h $w $f
	fi
}
encodeVideoWHF(){
 	ffmpeg -i "${1}" -s "${2}x${3}" -c:v ${videoEncoder} -b:v ${videoKbps}k -b:a ${audioKbps}k -c:a ${audioEncoder} -crf ${videoCRF} -filter:v fps=${4} -allow_sw 1 -movflags use_metadata_tags -map_metadata 0:g -loglevel error -stats "${5}"
	return $?
}



# Other functions
getTimestamp(){
	if [ $2 = true ]; then
		YMDHMS=$( getVideoTimestamp "${1}" )
	else
		YMDHMS=$( getImageTimestamp "${1}" )
	fi
	if [[ $YMDHMS = "" ]]; then
		if [ $3 = false ]; then echo ""; return; fi
		YMDHMS="9999 99 99 99 99 99"
		for t in "a"  "m"  "c"  "B" ; do
			R=$(stat -f "%S${t}" -t "%Y %m %d %H %M %S" "$1")
			if [[ $YMDHMS > $R ]]; then YMDHMS=$R;  fi
		done
	fi
	read year month day hour minute second <<< $YMDHMS
	echo "$year-$month-$day $hour.$minute.$second"
}
getNewSizeWH(){
	do_resize=false
	width=$1 ; height=$2 ; max_small_side=$3 ; max_large_side=$4
	if [ $width -gt $height ]; then
		is_portrait=false
		min_side=$height; max_side=$width
	else
		is_portrait=true
		min_side=$width;  max_side=$height
	fi
	if [[ $min_side -gt $max_small_side ]]; then
		do_resize=true
		(( max_side = max_small_side * max_side / min_side ))
		(( min_side = max_small_side ))
	fi
	if [[ $max_side -gt $max_large_side ]]; then
		do_resize=true
		(( min_side = max_large_side * min_side / max_side ))
		(( max_side= max_large_side ))
	fi
	if [ $is_portrait = true ]; then
		echo $min_side $max_side $do_resize
	else
		echo $max_side $min_side $do_resize
	fi
}



# Print actions and parameters ...
if [ $renameFiles = false -a $resizeImage = false -a $resizeVideo = false ]; then
	echo "Please, uses -r to rename and/or -i to resize image and/or -v to resize video, or -h to help."
	exit 1
fi
echo -n "Applying"
if [ $renameFiles = true ]; then
	echo -n " ${bold}renaming${normal}";
	if [ $resizeImage = true -a $resizeVideo = true ]; then echo -n ",";
	elif [ $resizeImage = true -o $resizeVideo = true ]; then echo -n " and"; fi
fi
if [ $resizeImage = true ]; then
	(( image_max_side = imageMaxPixelSmallSide * maxPixelLargeSideFactor ))
	echo -n " ${bold}image resampling${normal} [${imageMaxPixelSmallSide}~${image_max_side} and qlty=${imageQuality} using ${imageTools}]"
	if [ $resizeVideo = true ]; then echo -n " and "; fi
fi
if [ $resizeVideo = true ]; then
	(( video_max_side = videoMaxPixelSmallSide * maxPixelLargeSideFactor ))
	echo -n " ${bold}video coding${normal} [${videoMaxPixelSmallSide}~${video_max_side}, Mbps=v:${videoKbps}/a:${audioKbps}, FPS=${videoMaxFPS} and CRF=${videoCRF} using ${videoTools} v:${videoEncoder} a:${audioEncoder}]"
fi
echo "..."



# Processing all files in list ...
echo "Processing..."
for filename in "${listFiles[@]}"; do
	filename=$(python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$filename")
	extFilename=$(echo "${filename##*.}" | tr '[:upper:]' '[:lower:]')
	dirFilename=$(dirname "$filename")
	baseFilename=$(basename "$filename")
	if [ -z "${videoTypes##*$extFilename*}" ] ;then
		isVideo=true
	else
		isVideo=false
	fi

	# Check if need to resize
	do_resize=false
	if [ $isVideo = true ]; then
		read width height curFPS <<< $( getVideoSizeWHF "${filename}" )
		if [ $resizeVideo = true ]; then
			if [ "$width" != "" -a "$height" != "" -a "$curFPS" != "" ]; then # Ignore if there is no WIDTH, HEIGHT and FPS values
				read newWidth newHeight do_resize <<<$( getNewSizeWH $width $height $videoMaxPixelSmallSide $(( videoMaxPixelSmallSide * maxPixelLargeSideFactor )) )
				# Bash does not understand floating point arithmetic. It treats numbers containing a decimal point as strings. Using bc instead.
				if [ 1 -eq "$(echo "${curFPS} > ${videoMaxFPS}" | bc)" ]; then newFPS=$videoMaxFPS; do_resize=true; else newFPS=$curFPS; fi
				if [ $forceToRecreateFiles = true ]; then do_resize=true; fi
			fi
		fi
	else
		read width height <<< $( getImageSizeWH "${filename}" )
		if [ $resizeImage = true ]; then
			if [ "$width" != "" -a "$height" != "" ]; then # Ignore if there is no WIDTH and HEIGHT values
				read newWidth newHeight do_resize <<<$( getNewSizeWH $width $height $imageMaxPixelSmallSide $(( imageMaxPixelSmallSide * maxPixelLargeSideFactor )) )
				if [ $forceToRecreateFiles = true ]; then do_resize=true; fi
			fi
		fi
	fi

	# Check if need to rename
	do_rename=false
	if [ $do_resize = true ]; then
		if [ $isVideo = true ]; then
			newPathFilename=$( echo "${filename%.*}.${videoExtensionOutput}" )
			if [ "$filename" != "$newPathFilename" ]; then
				do_rename=true
			fi
		elif [ $forceJPEG = true ]; then
			newPathFilename=$( echo "${filename%.*}.${jpegExtension}" )
			if [ "$filename" != "$newPathFilename" ]; then
				do_rename=true
			fi
		else
			newPathFilename="${filename}"
		fi
	else
		newPathFilename="${filename}"
	fi
	if [ $renameFiles = true ]; then
		timestamp=$( getTimestamp "$newPathFilename" $isVideo $forceToRecreateFiles )
		if [ "$timestamp" != "" ]; then
			newFilename="$timestamp.$extFilename"
			if [ "$newPathFilename" != "$dirFilename/$newFilename" ]; then
				do_rename=true
				if [[ -e "${dirFilename}/${newFilename}" ]]; then
					for((i=1;i<9999;++i)); do
						if [[ ! -e "${dirFilename}/${timestamp}_${i}.${extFilename}" ]]; then
							newFilename="${dirFilename}/${timestamp}_${i}.${extFilename}"
							break
						fi
					done
				fi
				newPathFilename="$dirFilename/$newFilename"
			fi
		fi
	fi

	# Ask before to perform any action ...
	y=$answerYesToAll
	if [ $isVideo = true ]; then curFpsTxt="@${curFPS}" ; newFpsTxt="@${newFPS}"
	else                         curFpsTxt=""           ; newFpsTxt=""
	fi
	if [ $do_rename = true -a $do_resize = true ]; then
		echo -n "Update name and resolution of \"${filename}\" [${width}x${height}${curFpsTxt}] to \"${newPathFilename}\" [${newWidth}x${newHeight}${newFpsTxt}]"
	elif [ $do_rename = true ]; then
		echo -n "Update name from \"${filename}\" to \"${newPathFilename}\""
	elif [ $do_resize = true ]; then
		echo -n "Update resolution of \"${filename}\" from ${width}x${height}${curFpsTxt} to ${newWidth}x${newHeight}${newFpsTxt}"
	fi
	if [ $do_rename = true -o $do_resize = true ]; then if [ $answerYesToAll = false ]; then echo -n "? (press 'y' to yes, 'a' to all yes or another key to skip) "; else echo ""; fi; fi
	if [ $y = false ]; then
		if [ $do_rename = true -o $do_resize = true ]; then
			read ans
			case $ans in
				y) y=true ;;
				a) y=true; answerYesToAll=true ;;
				*) y=false ;;
			esac
		fi
	fi

	# Perform actions !
	if [ $y = true ] && [ $do_rename = true -o $do_resize = true ]; then
		origFilename="${dirFilename}/${dirNameWithOriginalFiles}/${baseFilename}"
		mkdir -p "${dirFilename}/${dirNameWithOriginalFiles}"
		mv "${filename}" "${origFilename}"
		if [ $do_resize = true ]; then
			if [ $isVideo = true ]; then
				encodeVideoWHF "${origFilename}" $newWidth $newHeight $newFPS "${newPathFilename}"
			else
				resampleImageWH "${origFilename}" $newWidth $newHeight "${newPathFilename}"
			fi
			if [ $? != 0 ]; then # Check if fail...
				echo "Error to process \"${filename}\". Keep the original..."
				if [ -f "${newPathFilename}" ]; then rm "${newPathFilename}"; fi # Remove the fail file ...
				mv "${origFilename}" "${filename}" # ... and rollback the original file.
			fi
		else
			if [ $keepOriginalFiles = true ]; then
				cp "${origFilename}" "${newPathFilename}"
			else
				mv "${origFilename}" "${newPathFilename}"
			fi
		fi
		if [ $keepOriginalFiles = false ]; then
			if [ -f "${origFilename}" ]; then rm "${origFilename}"; fi
			rmdir "${dirFilename}/${dirNameWithOriginalFiles}"
		fi
	else
		echo "Skiping file \"${filename}\" [${width}x${height}${curFpsTxt}]."
	fi
done
