#!/usr/bin/env bash

# ./feel_good_about_myself.sh $username [numDownloadWorkers=20]

# For each HN submission:
#   check if there is already a commit in history for this submission
#   if no commit exists, - download the submission data and get its timestamp
#                        - commit the changes with GIT_AUTHOR_DATE="$commitTime"
#                                               GIT_COMMITTER_DATE="$commitTime"
#

DOWNLOAD_TODO=
DOWNLOAD_WORKER_TODOS=()
COMMIT_TODO=
KEEP_WORKER_FIFO_OPEN_PIDS=()
CLEANUP_PIDS=()
CURL_TIMEOUT=10
DEFAULT_NUM_WORKERS=10

cleanup() {
    echo "Got sigint, cleaning up..."
    kill "${KEEP_WORKER_FIFO_OPEN_PIDS[@]}" >/dev/null 2>&1 || true
    kill "${CLEANUP_PIDS[@]}" >/dev/null 2>&1 || true
    jobs -p | xargs kill >/dev/null 2>&1 || true
}

trap cleanup SIGINT

usage() {
    echo "./feel_good_about_myself.sh username [numDownloadWorkers=10]" >&2
    echo "    username = your news.ycombinator.com username"
    echo "    numDownloadWorkers = number of parallel downloads (default 10)"
}

main() {
    local username="$1"
    shift

    local nWorkers=${1-$DEFAULT_NUM_WORKERS}

    if test -z "$username" ; then
        usage
        exit 1
    fi

    echo "username: $username"
    echo "download workers: $nWorkers"
    echo

    DOWNLOAD_TODO=$(mktemp -u)
    COMMIT_TODO=$(mktemp -u)

    mkfifo -m 0600 "$DOWNLOAD_TODO"
    mkfifo -m 0600 "$COMMIT_TODO"

    push_download_todo() {
        get_all_submission_ids "$username" \
            | filter_existing_submissions > "$DOWNLOAD_TODO"
    }

    read_download_todo() {
        while read -r line
        do
            echo "$line"
        done < "$DOWNLOAD_TODO"
    }

    push_download_todo &
    CLEANUP_PIDS+=($!)

    download_in_background "$nWorkers" > "$COMMIT_TODO" &
    CLEANUP_PIDS+=($!)

    commit_in_background &
    CLEANUP_PIDS+=($!)

    wait %1 %2 %3

    echo "Done - don't forget to push your super duper contributions!"
}


download_in_background() {
    local nWorkers="$1"
    shift

    make_worker_fifos "$nWorkers"
    keep_worker_fifos_open "$nWorkers"

    spread_download_queue_to_worker_fifos "$nWorkers" &

    run_workers "$nWorkers" &
}

commit_in_background() {
    local gitTime

    while read -r submissionId submissionTimestamp
    do
        gitTime="$(timestamp_to_git_date "$submissionTimestamp")"
        make_commit "$submissionId" "$gitTime"
    done < "$COMMIT_TODO"
}

get_all_submission_ids() {
    local username="$1"
    shift

    local itemsUrl="https://hacker-news.firebaseio.com/v0/user/${username}.json"

    local text
    text=$(curl -s "$itemsUrl")

    local afterSubmitted=${text#*\"submitted\"\:\[}
    local submissionIdCommaList=${afterSubmitted%\]\}*}

    local submissionIds=()

    IFS=', ' read -r -a submissionIds <<< "$submissionIdCommaList"

    for submissionId in "${submissionIds[@]}"
    do
        echo "$submissionId"
    done
}

filter_existing_submissions() {

    local commitSubstring

    while read -r submissionId
    do
        commitSubstring="https://news.ycombinator.com/item?id=$submissionId"

        if commit_exists "$commitSubstring" ; then
            echo "already committed: $submissionId" >&2
        else
            echo "$submissionId"
        fi

    done < /dev/stdin
}

timestamp_to_git_date() {
    local timestamp="$1"
    shift

    convert_date_or_fail() {
        local timestamp="$1"
        shift

        case "$OSTYPE" in
          darwin*)  date -u -r "$timestamp" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || return 1 ;;
          *)        date -d @"$timestamp" -u +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || return 1 ;;
        esac
    }

    local validDateRegex='^[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}\:[0-9]{2}\:[0-9]{2}$'

    local isodate
    isodate=$(convert_date_or_fail "$timestamp" || echo "fail")
    [[ "$isodate" == "fail" ]] && return 1

    [[ $isodate =~ $validDateRegex ]] || return 1

    echo "$isodate" | tr -d '[:space:]'
}

download_submission_timestamp() {
    local submissionId="$1"
    shift

    local submissionUrl="https://hacker-news.firebaseio.com/v0/item/${submissionId}.json?print=pretty"

    local timestamp=0
    timestamp=$(curl -s --max-time "$CURL_TIMEOUT" "$submissionUrl" | grep '"time"' | cut -d':' -f2- | cut -d' ' -f2- | cut -d',' -f1)

    echo "$submissionId $timestamp"
}

commit_exists() {
    return 1
    local commitSubstring="$1"
    shift

    git log --grep "$commitSubstring" 2>/dev/null | grep "$commitSubstring" >/dev/null \
        && return 0 || return 1
}

download_worker() {
    local workerId="$1"
    shift

    while read -r submissionId
    do
        download_submission_timestamp "$submissionId"
    done < "${DOWNLOAD_WORKER_TODOS[$workerId]}"
}

run_workers() {
    local nWorkers="$1"
    shift

    WAIT_FOR=()

    for ((workerId=0;workerId<="$nWorkers";workerId++)) ; do
        download_worker "$workerId" &
        WAIT_FOR+=($!)
    done

    wait "${WAIT_FOR[@]}"
}

make_worker_fifos() {
    local nWorkers="$1"
    shift

    make_worker_fifo() {
        local workerId="$1"
        shift
        local workerFifo

        workerFifo=$(mktemp -u)
        mkfifo -m 0600 "$workerFifo"
        DOWNLOAD_WORKER_TODOS[$workerId]="$workerFifo"
    }

    for ((workerId=0;workerId<="$nWorkers";workerId++)) ; do
        make_worker_fifo "$workerId"
    done
}

keep_worker_fifos_open() {
    local nWorkers="$1"
    shift

    keep_worker_fifo_open() {
        local workerId="$1"
        shift

        sleep 60000 > "${DOWNLOAD_WORKER_TODOS[$workerId]}" &
        KEEP_WORKER_FIFO_OPEN_PIDS+=($!)
    }

    for ((workerId=0;workerId<="$nWorkers";workerId++)) ; do
        keep_worker_fifo_open "$workerId"
    done
}

close_worker_fifos() {
    local nWorkers="$1"
    shift

    close_worker_fifo() {
        local workerId="$1"
        shift
    }
}

spread_download_queue_to_worker_fifos() {
    local nWorkers="$1"
    shift

    local counter=0
    while read -r submissionId
    do
        echo "$submissionId" >> "${DOWNLOAD_WORKER_TODOS[$counter]}"

        let counter=counter+1

        if test $counter -eq "$nWorkers" ; then
            let counter=0
        fi
    done < "$DOWNLOAD_TODO"

    kill "${KEEP_WORKER_FIFO_OPEN_PIDS[@]}"
    KEEP_WORKER_FIFO_OPEN_PIDS=()
}

make_commit() {
    local submissionId="$1"
    shift
    local commitTime="$1"
    shift

    local commitMessage="https://news.ycombinator.com/item?id=$submissionId"

    echo "commit $commitMessage at $commitTime"

    GIT_AUTHOR_DATE="$commitTime" GIT_COMMITTER_DATE="$commitTime" git commit --allow-empty -m "$commitMessage" >/dev/null 2>&1
}

main "$@"
