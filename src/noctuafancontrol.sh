#!/bin/bash

PWM_CHIP="/sys/class/pwm/pwmchip0"
PWM_ID="0"
PWM_PATH="$PWM_CHIP/pwm$PWM_ID"

PERIOD=40000
POLL_INTERVAL=2
RAMP_STEP_DELAY=0.02
RAMP_PERCENT_PER_STEP=2
HYSTERESIS=2

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

get_target_speed_from_temp() {
    local t=$1
    if [ $t -lt 40 ]; then echo 0
    elif [ $t -lt 45 ]; then echo 30
    elif [ $t -lt 50 ]; then echo 40
    elif [ $t -lt 55 ]; then echo 50
    elif [ $t -lt 60 ]; then echo 60
    elif [ $t -lt 65 ]; then echo 75
    elif [ $t -lt 70 ]; then echo 85
    else echo 100
    fi
}

apply_speed() {
    local target_percent=$1
    local target_duty=$(percent_to_duty $target_percent)
    local current_duty_raw=$(cat "$PWM_PATH/duty_cycle" 2>/dev/null || echo 0)
    if [ "$target_duty" -eq "$current_duty_raw" ]; then return; fi
    local step=$(percent_to_duty $RAMP_PERCENT_PER_STEP)
    if [ "$step" -eq 0 ]; then step=100; fi
    local temp_duty=$current_duty_raw
    while [ $temp_duty -ne $target_duty ]; do
        if [ $temp_duty -lt $target_duty ]; then
            temp_duty=$((temp_duty + step))
            if [ $temp_duty -gt $target_duty ]; then temp_duty=$target_duty; fi
        else
            temp_duty=$((temp_duty - step))
            if [ $temp_duty -lt $target_duty ]; then temp_duty=$target_duty; fi
        fi
        echo $temp_duty > "$PWM_PATH/duty_cycle"
        sleep $RAMP_STEP_DELAY
    done
}

cleanup() {
    echo $(percent_to_duty 100) > "$PWM_PATH/duty_cycle"
    exit 0
}

trap cleanup EXIT SIGTERM SIGINT

setup_pwm
LAST_TARGET=0

echo "Fan control started on: $THERMAL_FILE"

while true; do
    TEMP=$(get_cpu_temp)
    RAW_TARGET=$(get_target_speed_from_temp $TEMP)
    if [ "$RAW_TARGET" -lt "$LAST_TARGET" ]; then
        HYST_TEMP=$((TEMP + HYSTERESIS))
        HYST_TARGET=$(get_target_speed_from_temp $HYST_TEMP)
        if [ "$HYST_TARGET" -lt "$LAST_TARGET" ]; then
             FINAL_TARGET=$RAW_TARGET
        else
             FINAL_TARGET=$LAST_TARGET
        fi
    else
        FINAL_TARGET=$RAW_TARGET
    fi
    apply_speed $FINAL_TARGET
    LAST_TARGET=$FINAL_TARGET
    sleep $POLL_INTERVAL
done
