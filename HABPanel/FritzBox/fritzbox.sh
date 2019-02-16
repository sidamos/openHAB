#!/bin/bash
# 
# Script that downloads the call list from a fritz box and generates 
# html code than can be embedded into a habpanel widget that uses the 
# matrix-theme (https://community.openhab.org/t/custom-theme-in-habpanel-2-1-example/31100)
#
# If calls have been recorded, it additionally downloads the call recordings
# and adds a call to the widget that allows to play back the recording using
# the default audio sink of openHAB.
#
# Check and adapt the following environment variables to your needs:

# fritzbox URL for tr-064 calls
BASEURL="http://192.168.0.1:49000"
# user:password used to authenticate
USER="user:password"
# openhab directory containing sounds subdirectory
OPENHAB_DIR=PATH/conf
# call overview file
OUT=$OPENHAB_DIR/html/calloverview.html
# temporary directory
TMP=/tmp

# number of calls to show
COUNT=10
# number of answering machines
TAM_COUNT=2
# URL of the SVG file containing the icons
SVG_URL=/static/fritzbox.svg
# icon name for recorded calls
CASSETTE_NAME=cassette_100
# svg viewbox for recorded calls
CASSETTE_BOX="0 0 100 100"
# icon name for incoming calls
CALL_IN_NAME=phone-in_100
# svg viewbox for incoming calls
CALL_IN_BOX="0 0 100 100"
# icon name for outgoing calls
CALL_OUT_NAME=phone-out_100
# svg viewbox for outgoing calls
CALL_OUT_BOX="0 0 100 100"
# icon name for missed calles
CALL_MISSED_NAME=phone-missed_100
# svg viewbox for missed calls
CALL_MISSED_BOX="0 0 100 100"

### Function definitions ###

function getElement() {
  text=$1
  name=$2
 
  echo "$text" | sed -e "s/.*<$name>//" -e "s#</$name>.*##"
}

function arrayContains() {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

function soapCall() {
  URL=$1
  URN=$2
  ACTION=$3
  ELEMENT=$4
  PARAMETERS=${5:-}

  cat >$TMP/soapEnvelope-$$ <<EOF
<?xml version='1.0' encoding='utf-8'?>
<s:Envelope s:encodingStyle='http://schemas.xmlsoap.org/soap/encoding/' xmlns:s='http://schemas.xmlsoap.org/soap/envelope/'>
 <s:Body>
  <u:$ACTION xmlns:u='$URN'>${PARAMETERS}</u:$ACTION>
 </s:Body>
</s:Envelope>
EOF

  RESPONSE=$(curl -s --anyauth --user $USER $URL -H 'Content-Type: text/xml; charset="utf-8"' -H "SoapAction:$URN#$ACTION" --data @$TMP/soapEnvelope-$$)
  #cat $TMP/soapEnvelope-$$
  rm $TMP/soapEnvelope-$$

  if [ "x${ELEMENT}x" != "xx" ]; then
    echo $RESPONSE | grep $ELEMENT | sed -e "s/.*<$ELEMENT>//" -e "s#</$ELEMENT>.*##"
  else 
    echo $RESPONSE
  fi
}

function removeTamMessages() {
  rm $TMP/tam${1:-[0-9]}.xml 2>/dev/null
}

function downloadMissingTamMessages() {
  tamidx=0
  while [ $tamidx -lt $TAM_COUNT ]; do 
    if [ ! -f $TMP/tam${tamidx}.xml ]; then
      echo -n "downloading message list for TAM $tamidx..."
      URL=$(soapCall "$BASEURL/upnp/control/x_tam" "urn:dslforum-org:service:X_AVM-DE_TAM:1" GetMessageList NewURL "<NewIndex>${tamidx}</NewIndex>")
      wget --quiet -O - $URL | awk '/<Message>/,/<\/Message>/ { printf $0 } /<\/Message>/ { print }'>$TMP/tam${tamidx}.xml 
      echo "$(stat -c%s $TMP/tam${tamidx}.xml) bytes."
    fi

    tamidx=$(expr $tamidx + 1)
  done
}

function getTamMsg() {
  mdate=$1

  for tamxml in $TMP/tam${2:-[0-9]}.xml; do
    while read message; do
      date=$(getElement "$message" Date)

      if [ "${date}" == "${mdate}" ]; then
        echo "$message"
        return 0
      fi
    done < $tamxml
  done

  return 1
}

function updateCallOverview() {
  downloadMissingTamMessages

  URL=$(soapCall "$BASEURL/upnp/control/x_contact" "urn:dslforum-org:service:X_AVM-DE_OnTel:1" GetCallList NewCallListURL)

  echo "<div class=\"section\">">$OUT
  echo "<div class=\"title\"><div class=\"name\">Anrufliste</div></div>">>$OUT
  echo -n "<div class=\"controls\" ng-init=\"">>$OUT

  for i in `seq 0 $COUNT`; do
    echo -n "rec${i}='icon on';">>$OUT
  done 
  
  echo "\">">>$OUT
  echo "<table>">>$OUT

  callidx=0
  echo -n "downloading call list..."
  wget --quiet -O - $URL | grep Call > $TMP/calls.xml
  echo "$(stat -c%s $TMP/calls.xml) bytes."

  while read call; do
    type=$(getElement "$call" Type)
    caller=$(getElement "$call" Caller)
    called=$(getElement "$call" Called)
    name=$(getElement "$call" Name)
    date=$(getElement "$call" Date)
    duration=$(getElement "$call" Duration)
    path=$(getElement "$call" Path)

    message=$(getTamMsg "$date")

    [ "x${message}x" != "xx" ] && isTamMsg=1 || isTamMsg=0
    [ "x$(getElement "$message" New)x" == "x1x" ] && isNewTamMsg=1 || isNewTamMsg=0

    echo "processing call $date (isTamMsg=$isTamMsg isNewTamMsg=$isNewTamMsg)..."

    if [ "$path" == "$call" ]; then
      path=""

      # in case this call has no associated recording, check if there is a TAM message with the
      # same time and skip this call 
      if [ $isTamMsg -eq 1 ]; then
        echo "skipped (also has a TAM message)."
        continue
      fi

      echo "<div class=\"widget\">">>$OUT
    else 
      soundfile=${OPENHAB_DIR}/sounds/`basename $path`.wav

      # collect all current soundfiles to be able to delete the old ones
      files[callidx]=$soundfile

      if [ ! -f $soundfile ]; then
        echo -n "fetching ${soundfile}..."
	echo "${BASEURL}$path&$SID"

        curl -s -o $soundfile "${BASEURL}$path&$SID"
	echo $?

        echo "$(stat -c%s $soundfile) bytes."
      fi

      echo "<div class=\"widget\" ng-click=\"rec${callidx}='icon off'; sendCmd('AbMessage', '`basename $soundfile`')\">">>$OUT
    fi

    # 1 incoming
    # 2 missed
    # 3 outgoing
    # 9 active incoming
    #10 rejected incoming
    #11 active outgoing 
    if [ "x${path}x" != "xx" ]; then
      if [ $isNewTamMsg -ne 1 ]; then
        echo "<div class=\"icon off\"><svg viewBox=\"${CASSETTE_BOX}\"><use xlink:href=\"${SVG_URL}#${CASSETTE_NAME}\"></div>">>$OUT
      else 
        echo "<div class=\"{{rec$callidx}}\"><svg viewBox=\"${CASSETTE_BOX}\"><use xlink:href=\"${SVG_URL}#${CASSETTE_NAME}\"></div>">>$OUT
      fi
    elif [ $type -eq 1 -o $type -eq 9 ]; then
      echo "<div class=\"icon off\"><svg viewBox=\"${CALL_IN_BOX}\"><use xlink:href=\"${SVG_URL}#${CALL_IN_NAME}\"></div>">>$OUT
    elif [ $type -eq 2 ]; then
      echo "<div class=\"icon off\"><svg viewBox=\"${CALL_MISSED_BOX}\"><use xlink:href=\"${SVG_URL}#${CALL_MISSED_NAME}\"></div>">>$OUT
    elif [ $type -eq 3 -o $type -eq 11 ]; then
      echo "<div class=\"icon off\"><svg viewBox=\"${CALL_OUT_BOX}\"><use xlink:href=\"${SVG_URL}#${CALL_OUT_NAME}\"></div>">>$OUT
    fi

    echo "<div class=\"name\">">>$OUT
    if [ $type -eq 1 ]; then
      echo "${name:-$caller} ($duration)">>$OUT
    elif [ $type -eq 2 -o $type -eq 9 ]; then
      echo "${name:-$caller}">>$OUT
    elif [ $type -eq 3 ]; then
      echo "${name:-$called} ($duration)">>$OUT
    elif [ $type -eq 11 ]; then
      echo "${name:-$called}">>$OUT
    fi
    echo "</div>">>$OUT

    echo "<div class=\"valueGroup\"><div class=\"value\">$date</div></div>">>$OUT
    echo "</div>">>$OUT
    
    callidx=$(expr $callidx + 1)
    if [ $callidx -eq $COUNT ]; then
      break
    fi
  done < $TMP/calls.xml
  rm $TMP/calls.xml

  echo "</div></div>">>$OUT

  # remove old files
  for file in ${OPENHAB_DIR}/sounds/rec.[0-9].[0-9][0-9][0-9].wav; do
    arrayContains "$file" "${files[@]}"
    if [ $? -ne 0 -a -f $file ]; then
      rm ${file} 2>/dev/null
      echo "removed old recording $file."
    fi 
  done
}

function mark() {
  file=${OPENHAB_DIR}/sounds/$1

  tam=$(echo $1 | cut -d "." -f 2)
  index=$(echo $1 | cut -d "." -f 3)

  soapCall "$BASEURL/upnp/control/x_tam" "urn:dslforum-org:service:X_AVM-DE_TAM:1" MarkMessage dummy "<NewIndex>$tam</NewIndex><NewMessageIndex>$index</NewMessageIndex><NewMarkedAsRead>1</NewMarkedAsRead>"
}

### the fun starts here ###
source `dirname $0`/lockRoutines
exlock_now || exit 1

echo "lock obtained"

SID=$(soapCall "$BASEURL/upnp/control/deviceconfig" "urn:dslforum-org:service:DeviceConfig:1" "X_AVM-DE_CreateUrlSID" NewX_AVM-DE_UrlSID)

removeTamMessages

if [ $# -eq 1 -a "$1" == "update" ]; then
  updateCallOverview
elif [ $# -eq 2 -a "$1" == "mark" ]; then
  mark $2
  updateCallOverview
else
  echo "`basename $0` update | mark <file>"
  exit 1
fi

removeTamMessages

