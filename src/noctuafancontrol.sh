#!/bin/bash

PWM_CHIP="/sys/class/pwm/pwmchip0"
PWM_ID="0"
PWM_PATH="$PWM_CHIP/pwm$PWM_ID"

POLL_INTERVAL=3
RAMP_STEP_DELAY=0.02
RAMP_PERCENT_PER_STEP=2
HYSTERESIS=3

PERIOD=40000

find_cpu_sensor() {
    for zone in /sys/class/thermal/thermal_zone*; do
        if [ -f "$zone/type" ]; then
            TYPE=$(cat "$zone/type")
            if [[ "$TYPE" == *"soc-thermal"* ]] || [[ "$TYPE" == *"cpu"* ]]; then
                echo "$zone/temp"
                return
            fi
        fi
    done
    echo "/sys/class/thermal/thermal_zone0/temp"
}

THERMAL_FILE=$(find_cpu_sensor)

setup_pwm() {
    if [ ! -d "$PWM_PATH" ]; then
        echo $PWM_ID > "$PWM_CHIP/export" 2>/dev/null
        sleep 1
    fi
    echo 0 > "$PWM_PATH/enable" 2>/dev/null
    echo $PERIOD > "$PWM_PATH/period" 2>/dev/null
    echo "normal" > "$PWM_PATH/polarity" 2>/dev/null
    echo 1 > "$PWM_PATH/enable" 2>/dev/null
}

get_cpu_temp() {
    read -r RAW_TEMP < "$THERMAL_FILE"
    echo $((RAW_TEMP / 1000))
}

percent_to_duty() {
    local percent=$1
    if [ $percent -gt 100 ]; then percent=100; fi
    if [ $percent -lt 0 ]; then percent=0; fi
    echo $(( (percent * PERIOD) / 100 ))
}

current_duty=$(cat "$PWM_PATH/duty_cycle" 2>/dev/null || echo 0)

apply_speed() {
    local target_percent=$1
    local target_duty=$(percent_to_duty $target_percent)
    
    if [ $target_duty -eq $current_duty ]; then return; fi

    local step=$(percent_to_duty $RAMP_PERCENT_PER_STEP)
    if [ "$step" -eq 0 ]; then step=100; fi

    while [ $current_duty -ne $target_duty ]; do
        if [ $current_duty -lt $target_duty ]; then
            current_duty=$((current_duty + step))
            if [ $current_duty -gt $target_duty ]; then current_duty=$target_duty; fi
        else
            current_duty=$((current_duty - step))
            if [ $current_duty -lt $target_duty ]; then current_duty=$target_duty; fi
        fi
        
        echo $current_duty > "$PWM_PATH/duty_cycle"
        sleep $RAMP_STEP_DELAY
    done
}

cleanup() {
    local safe_duty=$(percent_to_duty 100)
    echo $safe_duty > "$PWM_PATH/duty_cycle"
    exit 0
}

trap cleanup EXIT SIGTERM SIGINT

setup_pwm

LAST_APPLIED_TARGET=0
LAST_TEMP_AT_CHANGE=0

while true; do
    TEMP=$(get_cpu_temp)
    
    if [ $TEMP -lt 40 ]; then
        CALC_TARGET=0
    elif [ $TEMP -lt 45 ]; then
        CALC_TARGET=30
    elif [ $TEMP -lt 50 ]; then
        CALC_TARGET=40
    elif [ $TEMP -lt 55 ]; then
        CALC_TARGET=50
    elif [ $TEMP -lt 60 ]; then
        CALC_TARGET=60
    elif [ $TEMP -lt 65 ]; then
        CALC_TARGET=75
    elif [ $TEMP -lt 70 ]; then
        CALC_TARGET=85
    else
        CALC_TARGET=100
    fi

    FINAL_TARGET=$CALC_TARGET

    if [ $CALC_TARGET -lt $LAST_APPLIED_TARGET ]; then
        if [ $TEMP -gt $((LAST_TEMP_AT_CHANGE - HYSTERESIS)) ]; then
            FINAL_TARGET=$LAST_APPLIED_TARGET
        fi
    fi

    apply_speed $FINAL_TARGET

    if [ $FINAL_TARGET -ne $LAST_APPLIED_TARGET ]; then
        LAST_APPLIED_TARGET=$FINAL_TARGET
        LAST_TEMP_AT_CHANGE=$TEMP
    fi

    sleep $POLL_INTERVAL
done
