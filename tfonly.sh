#!/usr/bin/env bash

: ${RESOURCE_PATTERN='(?<=#\s)[^\s]+'}
: ${ACTION_PATTERN='(?<=\sbe\s)[^\s]+'}
: ${TERRASPACE_STACK=}
: ${DRY_RUN=}

: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -e           Resource regex"
    echo "  -t stack     Terraspace stack to use. Uses terraform by default"
    echo "  -d           Dry run - show what would be done without actually doing it. Applies to move and remove actions only"
    echo "  -h           Show this help message"
    exit 0
} 


apply() { 
    
    local targets=()
    for resource in $@; do
        targets+=("-target=$resource")
    done
    
    if [[ -n "$TERRASPACE_STACK" ]];then
        terraspace up $TERRASPACE_STACK "${targets[@]}"
    else
        terraform apply "${targets[@]}"
    fi

    return
}

remove() {
    # local resources=("$@")
    # if [[ "$DRY_RUN" == true ]]; then
    #     resources=("-dry-run" ${resources[@]})
    # fi

    if [[ -n "$TERRASPACE_STACK" ]];then
        terraspace state rm "${DRY_RUN}" "$@"
    else
        terraform state rm "${DRY_RUN}" "$@"
    fi
}

move() {
    #local resources=("$@")
    # if [[ "$DRY_RUN" == true ]]; then
    #     resources=("-dry-run" ${resources[@]})
    # fi

    exec 3>&1
    script=$(dialog --title "Terraform Only" --clear \
    --inputbox "Enter the sed script to transform resource names (eg. s/old/new/):" 0 0 2>&1 1>&3)

    return_value=$?
    exec 3>&-

    case $return_value in
        $DIALOG_OK)
            echo "Sed script: $script"
            for resource in $@; do
                new_resource=$(sed -E "$script" <<< "$resource")
                if [[ -n "$TERRASPACE_STACK" ]];then
                    terraspace state mv "${DRY_RUN}" "$resource" "$new_resource"
                else
                    terraform state mv "${DRY_RUN}" "$resource" "$new_resource"
                fi
            done
            ;;
        $DIALOG_CANCEL|$DIALOG_ESC|$DIALOG_EXTRA)
            return
            ;;
        *)
            echo "An unexpected error occurred."
            exit 1
            ;;
    esac
}


menu() {
     #local selected_resources=("$@")

    exec 3>&1
    action=$(dialog --title "Terraform Only" --clear \
    --menu "Select an action to perform on the selected resources:" 0 0 0 \
    "apply" "Apply the selected resources" \
    "remove" "Remove the selected resources" \
    "move" "Move the selected resources" 2>&1 1>&3)
    
    return_value=$?
    exec 3>&-

    case $return_value in
        $DIALOG_OK)
            #"$action" "${selected_resources[@]}"
            "$action" "$@"
            ;;
        $DIALOG_CANCEL|$DIALOG_ESC|$DIALOG_EXTRA)
            return
            ;;
        *)
            echo "An unexpected error occurred."
            exit 1
            ;;
    esac
}



main() {
    declare -A resources

    if [[ -n "$TERRASPACE_STACK" ]];then
        plan=$(terraspace plan "$TERRASPACE_STACK")
    else
        plan=$(terraform plan)
    fi

    while read -r line; do
        resource=$(grep -Po "$RESOURCE_PATTERN" <<< "$line"| sed 's/\x1b\[[0-9;]*m//g')
        if [[ -n "$resource" ]]; then
            action=$(grep -Po "$ACTION_PATTERN" <<< "$line"| sed 's/\x1b\[[0-9;]*m//g')
            if [[ -n "$action" ]]; then    
                # if [[ "$action" =~ destroyed ]]; then
                #     action="destroyed"
                # elif [[ "$action" =~ replaced ]]; then
                #     action="replaced"
                # fi
                resources["$resource"]="$action"
            fi
        fi
    done <<< "$plan"

    if [[ ${#resources[@]} -eq 0 ]]; then
        echo "No resources found matching the pattern."
        return
    fi

    
    options=()
    for resource in "${!resources[@]}"; do
        options+=("$resource" "${resources[$resource]}" "off")
    done

    exec 3>&1
    selected=$(dialog --title "Terraform Only" --clear --single-quoted \
    --checklist "Select resources to apply:" 0 0 0 \
    ${options[@]} 2>&1 1>&3)

    return_value=$?
    exec 3>&-

    case $return_value in
        $DIALOG_OK)
            menu "$selected"
            ;;
        $DIALOG_CANCEL|$DIALOG_ESC|$DIALOG_EXTRA)
            return
            ;;
        *)
            echo "An unexpected error occurred."
            exit 1
            ;;
    esac
}


while getopts "de:t:h" opt; do
    case "$opt" in
        e)
            RESOURCE_PATTERN="$OPTARG"
            ;;
        t)
            TERRASPACE_STACK="$OPTARG"
            ;;
        d)
            DRY_RUN="-dry-run"
            ;;
        h)
            help
            ;;
    esac
done

main "$@"
