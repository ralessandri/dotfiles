alias untar="tar xfv"
alias tarl="tar tf"

# Function to list the first N levels of a tar archive
tarln() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: tarln <archive.tar> <depth>"
        return 1
    fi

    local archive="$1"
    local depth="$2"

    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        echo "Error: depth must be a positive number"
        return 1
    fi

    tar -tf "$archive" | awk -v depth="$depth" -F/ '
    {
        output=$1
        for(i=2; i<=depth && i<=NF; i++) {
            output=output"/"$i
        }
        print output
    }' | sort -u
}

untarto() {
    # Usage check
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: untarto <archive> <target_dir> [folder_inside_archive]"
        return 1
    fi

    local archive="$1"
    local target="$2"
    local folder_inside="${3:-}"  # optional

    # Create target directory if it does not exist
    mkdir -p "$target"

    # Extract either the whole archive or a specific folder
    if [ -n "$folder_inside" ]; then
        tar -xf "$archive" -C "$target" "$folder_inside"
    else
        tar -xf "$archive" -C "$target"
    fi
}
