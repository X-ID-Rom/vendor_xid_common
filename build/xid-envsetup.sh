function __print_lineage_functions_help() {
cat <<EOF
Additional LineageOS functions:
- cout:            Changes directory to out.
- mmp:             Builds all of the modules in the current directory and pushes them to the device.
- mmap:            Builds all of the modules in the current directory and its dependencies, then pushes the package to the device.
- mmmp:            Builds all of the modules in the supplied directories and pushes them to the device.
- lineagegerrit:   A Git wrapper that fetches/pushes patch from/to LineageOS Gerrit Review.
- lineagerebase:   Rebase a Gerrit change and push it again.
- lineageremote:   Add git remote for LineageOS Gerrit Review.
- aospremote:      Add git remote for matching AOSP repository.
- cloremote:       Add git remote for matching CodeLinaro repository.
- githubremote:    Add git remote for LineageOS Github.
- mka:             Builds using SCHED_BATCH on all processors.
- mkap:            Builds the module(s) using mka and pushes them to the device.
- cmka:            Cleans and builds using mka.
- repodiff:        Diff 2 different branches or tags within the same repo
- repolastsync:    Prints date and time of last repo sync.
- reposync:        Parallel repo sync using ionice and SCHED_BATCH.
- repopick:        Utility to fetch changes from Gerrit.
- sort-blobs-list: Sort proprietary-files.txt sections with LC_ALL=C.
- installboot:     Installs a boot.img to the connected device.
- installrecovery: Installs a recovery.img to the connected device.
EOF
}

function mk_timer()
{
    local start_time=$(date +"%s")
    $@
    local ret=$?
    local end_time=$(date +"%s")
    local tdiff=$(($end_time-$start_time))
    local hours=$(($tdiff / 3600 ))
    local mins=$((($tdiff % 3600) / 60))
    local secs=$(($tdiff % 60))
    local ncolors=$(tput colors 2>/dev/null)
    echo
    if [ $ret -eq 0 ] ; then
        echo -n "#### make completed successfully "
    else
        echo -n "#### make failed to build some targets "
    fi
    if [ $hours -gt 0 ] ; then
        printf "(%02g:%02g:%02g (hh:mm:ss))" $hours $mins $secs
    elif [ $mins -gt 0 ] ; then
        printf "(%02g:%02g (mm:ss))" $mins $secs
    elif [ $secs -gt 0 ] ; then
        printf "(%s seconds)" $secs
    fi
    echo " ####"
    echo
    return $ret
}

function compile_device()
{
    breakfast $*
    if [ $? -eq 0 ]; then
        mka bacon
    else
        echo "No such item in brunch menu. Try 'breakfast'"
        return 1
    fi
    return $?
}

alias brunch=compile_device

function init_device()
{
    target=$1
    local variant=$2

    if [ $# -eq 0 ]; then
        # No arguments, so let's have the full menu
        lunch
    else
        if [[ "$target" =~ -(user|userdebug|eng)$ ]]; then
            # A buildtype was specified, assume a full device name
            lunch $target
        else
            # This is probably just the Lineage model name
            if [ -z "$variant" ]; then
                variant="userdebug"
            fi

            lunch xid_$target-$variant
        fi
    fi
    return $?
}

alias breakfast=init_device
alias bib=init_device

function cout()
{
    if [  "$OUT" ]; then
        cd $OUT
    else
        echo "Couldn't locate out directory.  Try setting OUT."
    fi
}


function installboot()
{
    if [ ! -e "$OUT/recovery/root/system/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/boot.img" ];
    then
        echo "No boot.img found. Run make bootimage first."
        return 1
    fi
    PARTITION=`grep "^\/boot" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/boot[[:space:]]" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine boot partition."
            return 1
        fi
    fi
    adb wait-for-device-recovery
    adb root
    adb wait-for-device-recovery
    if (adb shell getprop ro.lineage.device | grep -q "$LINEAGE_BUILD");
    then
        adb push $OUT/boot.img /cache/
        adb shell dd if=/cache/boot.img of=$PARTITION
        adb shell rm -rf /cache/boot.img
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $LINEAGE_BUILD, run away!"
    fi
}

function installrecovery()
{
    if [ ! -e "$OUT/recovery/root/system/etc/recovery.fstab" ];
    then
        echo "No recovery.fstab found. Build recovery first."
        return 1
    fi
    if [ ! -e "$OUT/recovery.img" ];
    then
        echo "No recovery.img found. Run make recoveryimage first."
        return 1
    fi
    PARTITION=`grep "^\/recovery" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $3'}`
    if [ -z "$PARTITION" ];
    then
        # Try for RECOVERY_FSTAB_VERSION = 2
        PARTITION=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $1'}`
        PARTITION_TYPE=`grep "[[:space:]]\/recovery[[:space:]]" $OUT/recovery/root/system/etc/recovery.fstab | awk {'print $3'}`
        if [ -z "$PARTITION" ];
        then
            echo "Unable to determine recovery partition."
            return 1
        fi
    fi
    adb wait-for-device-recovery
    adb root
    adb wait-for-device-recovery
    if (adb shell getprop ro.lineage.device | grep -q "$LINEAGE_BUILD");
    then
        adb push $OUT/recovery.img /cache/
        adb shell dd if=/cache/recovery.img of=$PARTITION
        adb shell rm -rf /cache/recovery.img
        echo "Installation complete."
    else
        echo "The connected device does not appear to be $LINEAGE_BUILD, run away!"
    fi
}

function makerecipe() {
    if [ -z "$1" ]
    then
        echo "No branch name provided."
        return 1
    fi
    cd android
    sed -i s/'default revision=.*'/'default revision="refs\/heads\/'$1'"'/ default.xml
    git commit -a -m "$1"
    cd ..

    repo forall -c '

    if [ "$REPO_REMOTE" = "github" ]
    then
        pwd
        lineageremote
        git push lineage HEAD:refs/heads/'$1'
    fi
    '
}

function lineagegerrit() {
    if [ "$(basename $SHELL)" = "zsh" ]; then
        # zsh does not define FUNCNAME, derive from funcstack
        local FUNCNAME=$funcstack[1]
    fi

    if [ $# -eq 0 ]; then
        $FUNCNAME help
        return 1
    fi
    local user=`git config --get review.review.lineageos.org.username`
    local review=`git config --get remote.github.review`
    local project=`git config --get remote.github.projectname`
    local command=$1
    shift
    case $command in
        help)
            if [ $# -eq 0 ]; then
                cat <<EOF
Usage:
    $FUNCNAME COMMAND [OPTIONS] [CHANGE-ID[/PATCH-SET]][{@|^|~|:}ARG] [-- ARGS]

Commands:
    fetch   Just fetch the change as FETCH_HEAD
    help    Show this help, or for a specific command
    pull    Pull a change into current branch
    push    Push HEAD or a local branch to Gerrit for a specific branch

Any other Git commands that support refname would work as:
    git fetch URL CHANGE && git COMMAND OPTIONS FETCH_HEAD{@|^|~|:}ARG -- ARGS

See '$FUNCNAME help COMMAND' for more information on a specific command.

Example:
    $FUNCNAME checkout -b topic 1234/5
works as:
    git fetch http://DOMAIN/p/PROJECT refs/changes/34/1234/5 \\
      && git checkout -b topic FETCH_HEAD
will checkout a new branch 'topic' base on patch-set 5 of change 1234.
Patch-set 1 will be fetched if omitted.
EOF
                return
            fi
            case $1 in
                __cmg_*) echo "For internal use only." ;;
                changes|for)
                    if [ "$FUNCNAME" = "lineagegerrit" ]; then
                        echo "'$FUNCNAME $1' is deprecated."
                    fi
                    ;;
                help) $FUNCNAME help ;;
                fetch|pull) cat <<EOF
usage: $FUNCNAME $1 [OPTIONS] CHANGE-ID[/PATCH-SET]

works as:
    git $1 OPTIONS http://DOMAIN/p/PROJECT \\
      refs/changes/HASH/CHANGE-ID/{PATCH-SET|1}

Example:
    $FUNCNAME $1 1234
will $1 patch-set 1 of change 1234
EOF
                    ;;
                push) cat <<EOF
usage: $FUNCNAME push [OPTIONS] [LOCAL_BRANCH:]REMOTE_BRANCH

works as:
    git push OPTIONS ssh://USER@DOMAIN:29418/PROJECT \\
      {LOCAL_BRANCH|HEAD}:refs/for/REMOTE_BRANCH

Example:
    $FUNCNAME push fix6789:gingerbread
will push local branch 'fix6789' to Gerrit for branch 'gingerbread'.
HEAD will be pushed from local if omitted.
EOF
                    ;;
                *)
                    $FUNCNAME __cmg_err_not_supported $1 && return
                    cat <<EOF
usage: $FUNCNAME $1 [OPTIONS] CHANGE-ID[/PATCH-SET][{@|^|~|:}ARG] [-- ARGS]

works as:
    git fetch http://DOMAIN/p/PROJECT \\
      refs/changes/HASH/CHANGE-ID/{PATCH-SET|1} \\
      && git $1 OPTIONS FETCH_HEAD{@|^|~|:}ARG -- ARGS
EOF
                    ;;
            esac
            ;;
        __cmg_get_ref)
            $FUNCNAME __cmg_err_no_arg $command $# && return 1
            local change_id patchset_id hash
            case $1 in
                */*)
                    change_id=${1%%/*}
                    patchset_id=${1#*/}
                    ;;
                *)
                    change_id=$1
                    patchset_id=1
                    ;;
            esac
            hash=$(($change_id % 100))
            case $hash in
                [0-9]) hash="0$hash" ;;
            esac
            echo "refs/changes/$hash/$change_id/$patchset_id"
            ;;
        fetch|pull)
            $FUNCNAME __cmg_err_no_arg $command $# help && return 1
            $FUNCNAME __cmg_err_not_repo && return 1
            local change=$1
            shift
            git $command $@ http://$review/p/$project \
                $($FUNCNAME __cmg_get_ref $change) || return 1
            ;;
        push)
            $FUNCNAME __cmg_err_no_arg $command $# help && return 1
            $FUNCNAME __cmg_err_not_repo && return 1
            if [ -z "$user" ]; then
                echo >&2 "Gerrit username not found."
                return 1
            fi
            local local_branch remote_branch
            case $1 in
                *:*)
                    local_branch=${1%:*}
                    remote_branch=${1##*:}
                    ;;
                *)
                    local_branch=HEAD
                    remote_branch=$1
                    ;;
            esac
            shift
            git push $@ ssh://$user@$review:29418/$project \
                ${local_branch}:refs/for/$remote_branch || return 1
            ;;
        changes|for)
            if [ "$FUNCNAME" = "lineagegerrit" ]; then
                echo >&2 "'$FUNCNAME $command' is deprecated."
            fi
            ;;
        __cmg_err_no_arg)
            if [ $# -lt 2 ]; then
                echo >&2 "'$FUNCNAME $command' missing argument."
            elif [ $2 -eq 0 ]; then
                if [ -n "$3" ]; then
                    $FUNCNAME help $1
                else
                    echo >&2 "'$FUNCNAME $1' missing argument."
                fi
            else
                return 1
            fi
            ;;
        __cmg_err_not_repo)
            if [ -z "$review" -o -z "$project" ]; then
                echo >&2 "Not currently in any reviewable repository."
            else
                return 1
            fi
            ;;
        __cmg_err_not_supported)
            $FUNCNAME __cmg_err_no_arg $command $# && return
            case $1 in
                #TODO: filter more git commands that don't use refname
                init|add|rm|mv|status|clone|remote|bisect|config|stash)
                    echo >&2 "'$FUNCNAME $1' is not supported."
                    ;;
                *) return 1 ;;
            esac
            ;;
    #TODO: other special cases?
        *)
            $FUNCNAME __cmg_err_not_supported $command && return 1
            $FUNCNAME __cmg_err_no_arg $command $# help && return 1
            $FUNCNAME __cmg_err_not_repo && return 1
            local args="$@"
            local change pre_args refs_arg post_args
            case "$args" in
                *--\ *)
                    pre_args=${args%%-- *}
                    post_args="-- ${args#*-- }"
                    ;;
                *) pre_args="$args" ;;
            esac
            args=($pre_args)
            pre_args=
            if [ ${#args[@]} -gt 0 ]; then
                change=${args[${#args[@]}-1]}
            fi
            if [ ${#args[@]} -gt 1 ]; then
                pre_args=${args[0]}
                for ((i=1; i<${#args[@]}-1; i++)); do
                    pre_args="$pre_args ${args[$i]}"
                done
            fi
            while ((1)); do
                case $change in
                    ""|--)
                        $FUNCNAME help $command
                        return 1
                        ;;
                    *@*)
                        if [ -z "$refs_arg" ]; then
                            refs_arg="@${change#*@}"
                            change=${change%%@*}
                        fi
                        ;;
                    *~*)
                        if [ -z "$refs_arg" ]; then
                            refs_arg="~${change#*~}"
                            change=${change%%~*}
                        fi
                        ;;
                    *^*)
                        if [ -z "$refs_arg" ]; then
                            refs_arg="^${change#*^}"
                            change=${change%%^*}
                        fi
                        ;;
                    *:*)
                        if [ -z "$refs_arg" ]; then
                            refs_arg=":${change#*:}"
                            change=${change%%:*}
                        fi
                        ;;
                    *) break ;;
                esac
            done
            $FUNCNAME fetch $change \
                && git $command $pre_args FETCH_HEAD$refs_arg $post_args \
                || return 1
            ;;
    esac
}

function lineagerebase() {
    local repo=$1
    local refs=$2
    local pwd="$(pwd)"
    local dir="$(gettop)/$repo"

    if [ -z $repo ] || [ -z $refs ]; then
        echo "LineageOS Gerrit Rebase Usage: "
        echo "      lineagerebase <path to project> <patch IDs on Gerrit>"
        echo "      The patch IDs appear on the Gerrit commands that are offered."
        echo "      They consist on a series of numbers and slashes, after the text"
        echo "      refs/changes. For example, the ID in the following command is 26/8126/2"
        echo ""
        echo "      git[...]ges_apps_Camera refs/changes/26/8126/2 && git cherry-pick FETCH_HEAD"
        echo ""
        return
    fi

    if [ ! -d $dir ]; then
        echo "Directory $dir doesn't exist in tree."
        return
    fi
    cd $dir
    repo=$(cat .git/config  | grep git://github.com | awk '{ print $NF }' | sed s#git://github.com/##g)
    echo "Starting branch..."
    repo start tmprebase .
    echo "Bringing it up to date..."
    repo sync .
    echo "Fetching change..."
    git fetch "http://review.lineageos.org/p/$repo" "refs/changes/$refs" && git cherry-pick FETCH_HEAD
    if [ "$?" != "0" ]; then
        echo "Error cherry-picking. Not uploading!"
        return
    fi
    echo "Uploading..."
    repo upload .
    echo "Cleaning up..."
    repo abandon tmprebase .
    cd $pwd
}

function mka() {
    m "$@"
}

function cmka() {
    if [ ! -z "$1" ]; then
        for i in "$@"; do
            case $i in
                bacon|otapackage|systemimage)
                    mka installclean
                    mka $i
                    ;;
                *)
                    mka clean-$i
                    mka $i
                    ;;
            esac
        done
    else
        mka clean
        mka
    fi
}

function repolastsync() {
    RLSPATH="$ANDROID_BUILD_TOP/.repo/.repo_fetchtimes.json"
    RLSLOCAL=$(date -d "$(stat -c %z $RLSPATH)" +"%e %b %Y, %T %Z")
    RLSUTC=$(date -d "$(stat -c %z $RLSPATH)" -u +"%e %b %Y, %T %Z")
    echo "Last repo sync: $RLSLOCAL / $RLSUTC"
}

function reposync() {
    repo sync -j$(nproc --all) "$@"
}

function repodiff() {
    if [ -z "$*" ]; then
        echo "Usage: repodiff <ref-from> [[ref-to] [--numstat]]"
        return
    fi
    diffopts=$* repo forall -c \
      'echo "$REPO_PATH ($REPO_REMOTE)"; git diff ${diffopts} 2>/dev/null ;'
}

# Return success if adb is up and not in recovery
function _adb_connected {
    {
        if [[ "$(adb get-state)" == device ]]
        then
            return 0
        fi
    } 2>/dev/null

    return 1
};

# Credit for color strip sed: http://goo.gl/BoIcm
function dopush()
{
    local func=$1
    shift

    adb start-server # Prevent unexpected starting server message from adb get-state in the next line
    if ! _adb_connected; then
        echo "No device is online. Waiting for one..."
        echo "Please connect USB and/or enable USB debugging"
        until _adb_connected; do
            sleep 1
        done
        echo "Device Found."
    fi

    if (adb shell getprop ro.lineage.device | grep -q "$LINEAGE_BUILD") || [ "$FORCE_PUSH" = "true" ];
    then
    # retrieve IP and PORT info if we're using a TCP connection
    TCPIPPORT=$(adb devices \
        | egrep '^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]):[0-9]+[^0-9]+' \
        | head -1 | awk '{print $1}')
    adb root &> /dev/null
    sleep 0.3
    if [ -n "$TCPIPPORT" ]
    then
        # adb root just killed our connection
        # so reconnect...
        adb connect "$TCPIPPORT"
    fi
    adb wait-for-device &> /dev/null
    adb remount &> /dev/null

    mkdir -p $OUT
    ($func $*|tee $OUT/.log;return ${PIPESTATUS[0]})
    ret=$?;
    if [ $ret -ne 0 ]; then
        rm -f $OUT/.log;return $ret
    fi

    is_gnu_sed=`sed --version | head -1 | grep -c GNU`

    # Install: <file>
    if [ $is_gnu_sed -gt 0 ]; then
        LOC="$(cat $OUT/.log | sed -r -e 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' -e 's/^\[ {0,2}[0-9]{1,3}% [0-9]{1,6}\/[0-9]{1,6}\] +//' \
            | grep '^Install: ' | cut -d ':' -f 2)"
    else
        LOC="$(cat $OUT/.log | sed -E "s/"$'\E'"\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" -E "s/^\[ {0,2}[0-9]{1,3}% [0-9]{1,6}\/[0-9]{1,6}\] +//" \
            | grep '^Install: ' | cut -d ':' -f 2)"
    fi

    # Copy: <file>
    if [ $is_gnu_sed -gt 0 ]; then
        LOC="$LOC $(cat $OUT/.log | sed -r -e 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' -e 's/^\[ {0,2}[0-9]{1,3}% [0-9]{1,6}\/[0-9]{1,6}\] +//' \
            | grep '^Copy: ' | cut -d ':' -f 2)"
    else
        LOC="$LOC $(cat $OUT/.log | sed -E "s/"$'\E'"\[([0-9]{1,3}((;[0-9]{1,3})*)?)?[m|K]//g" -E 's/^\[ {0,2}[0-9]{1,3}% [0-9]{1,6}\/[0-9]{1,6}\] +//' \
            | grep '^Copy: ' | cut -d ':' -f 2)"
    fi

    # If any files are going to /data, push an octal file permissions reader to device
    if [ -n "$(echo $LOC | egrep '(^|\s)/data')" ]; then
        CHKPERM="/data/local/tmp/chkfileperm.sh"
(
cat <<'EOF'
#!/system/bin/sh
FILE=$@
if [ -e $FILE ]; then
    ls -l $FILE | awk '{k=0;for(i=0;i<=8;i++)k+=((substr($1,i+2,1)~/[rwx]/)*2^(8-i));if(k)printf("%0o ",k);print}' | cut -d ' ' -f1
fi
EOF
) > $OUT/.chkfileperm.sh
        echo "Pushing file permissions checker to device"
        adb push $OUT/.chkfileperm.sh $CHKPERM
        adb shell chmod 755 $CHKPERM
        rm -f $OUT/.chkfileperm.sh
    fi

    RELOUT=$(echo $OUT | sed "s#^${ANDROID_BUILD_TOP}/##")

    stop_n_start=false
    for TARGET in $(echo $LOC | tr " " "\n" | sed "s#.*${RELOUT}##" | sort | uniq); do
        # Make sure file is in $OUT/{system,system_ext,data,odm,oem,product,product_services,vendor}
        case $TARGET in
            /system/*|/system_ext/*|/data/*|/odm/*|/oem/*|/product/*|/product_services/*|/vendor/*)
                # Get out file from target (i.e. /system/bin/adb)
                FILE=$OUT$TARGET
            ;;
            *) continue ;;
        esac

        case $TARGET in
            /data/*)
                # fs_config only sets permissions and se labels for files pushed to /system
                if [ -n "$CHKPERM" ]; then
                    OLDPERM=$(adb shell $CHKPERM $TARGET)
                    OLDPERM=$(echo $OLDPERM | tr -d '\r' | tr -d '\n')
                    OLDOWN=$(adb shell ls -al $TARGET | awk '{print $2}')
                    OLDGRP=$(adb shell ls -al $TARGET | awk '{print $3}')
                fi
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
                if [ -n "$OLDPERM" ]; then
                    echo "Setting file permissions: $OLDPERM, $OLDOWN":"$OLDGRP"
                    adb shell chown "$OLDOWN":"$OLDGRP" $TARGET
                    adb shell chmod "$OLDPERM" $TARGET
                else
                    echo "$TARGET did not exist previously, you should set file permissions manually"
                fi
                adb shell restorecon "$TARGET"
            ;;
            */SystemUI.apk|*/framework/*)
                # Only need to stop services once
                if ! $stop_n_start; then
                    adb shell stop
                    stop_n_start=true
                fi
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
            ;;
            *)
                echo "Pushing: $TARGET"
                adb push $FILE $TARGET
            ;;
        esac
    done
    if [ -n "$CHKPERM" ]; then
        adb shell rm $CHKPERM
    fi
    if $stop_n_start; then
        adb shell start
    fi
    rm -f $OUT/.log
    return 0
    else
        echo "The connected device does not appear to be $LINEAGE_BUILD, run away!"
    fi
}

alias mmp='dopush mm'
alias mmmp='dopush mmm'
alias mmap='dopush mma'
alias mmmap='dopush mmma'
alias mkap='dopush mka'
alias cmkap='dopush cmka'


function sort-blobs-list() {
    T=$(gettop)
    $T/tools/extract-utils/sort-blobs-list.py $@
}

function fixup_common_out_dir() {
    common_out_dir=$(get_build_var OUT_DIR)/target/common
    target_device=$(get_build_var TARGET_DEVICE)
    common_target_out=common-${target_device}
    if [ ! -z $LINEAGE_FIXUP_COMMON_OUT ]; then
        if [ -d ${common_out_dir} ] && [ ! -L ${common_out_dir} ]; then
            mv ${common_out_dir} ${common_out_dir}-${target_device}
            ln -s ${common_target_out} ${common_out_dir}
        else
            [ -L ${common_out_dir} ] && rm ${common_out_dir}
            mkdir -p ${common_out_dir}-${target_device}
            ln -s ${common_target_out} ${common_out_dir}
        fi
    else
        [ -L ${common_out_dir} ] && rm ${common_out_dir}
        mkdir -p ${common_out_dir}
    fi
}
