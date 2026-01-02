#!/bin/bash
CARD="3"
amixer -c $CARD cset name='Main Mic Switch' on
amixer -c $CARD cset name='Differential Mux' 1
amixer -c $CARD cset name='Left PGA Mux' 'DifferentialL'
amixer -c $CARD cset name='Right PGA Mux' 'DifferentialR'
amixer -c $CARD cset name='Left Channel Capture Volume' 8
amixer -c $CARD cset name='Right Channel Capture Volume' 8
amixer -c $CARD cset name='ADC MIC' 8
amixer -c $CARD cset name='Capture Digital Volume' 192
amixer -c $CARD cset name='ALC Capture Function' 0

exit 0
