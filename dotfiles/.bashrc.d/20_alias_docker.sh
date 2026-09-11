############################################################################
#                                                                          #
#               ------- Useful Docker Aliases --------                     #
#                                                                          #
#     # Installation :                                                     #
#     copy/paste these lines into your .bashrc or .zshrc file or just      #
#     type the following in your current shell to try it out:              #
#     wget -O - https://gist.githubusercontent.com/jgrodziski/9ed4a17709baad10dbcd4530b60dfcbb/raw/d84ef1741c59e7ab07fb055a70df1830584c6c18/docker-aliases.sh | bash
#                                                                          #
#     # Usage:                                                             #
#     daws <svc> <cmd> <opts> : aws cli in docker with <svc> <cmd> <opts>  #
#     dc             : docker compose                                      #
#     dcu            : docker compose up -d                                #
#     dcd            : docker compose down                                 #
#     dcr            : docker compose run                                  #
#     dex <container>: execute a bash shell inside the RUNNING <container> #
#     di <container> : docker inspect <container>                          #
#     dim            : docker images                                       #
#     dip            : IP addresses of all running containers              #
#     dl <container> : docker logs -f <container>                          #
#     dnames         : names of all running containers                     #
#     dps            : docker ps                                           #
#     dpsa           : docker ps -a                                        #
#     drmc           : remove all exited containers                        #
#     drmid          : remove all dangling images                          #
#     drun <image>   : execute a bash shell in NEW container from <image>  #
#     dsr <container>: stop then remove <container>                        #
#                                                                          #
############################################################################

# List the names of running Docker containers
function dnames-fn {
	for ID in `docker ps | awk '{print $1}' | grep -v 'CONTAINER'`
	do
    	docker inspect $ID | grep Name | head -1 | awk '{print $2}' | sed 's/,//g' | sed 's%/%%g' | sed 's/"//g'
	done
}

# List IP addresses of running Docker containers
function dip-fn {
    echo "IP addresses of all named running containers"

    for DOC in `dnames-fn`
    do
        IP=`docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$DOC"`
        OUT+=$DOC'\t'$IP'\n'
    done
    echo -e $OUT | column -t
    unset OUT
}

# Open a shell in a running Docker container
function dex-fn {
	docker exec -it $1 ${2:-bash}
}

# Inspect a Docker container or image
function di-fn {
	docker inspect $1
}

# Follow logs from a Docker container
function dl-fn {
	docker logs -f $1
}

# Run a new Docker container interactively
function drun-fn {
	docker run -it $1 $2
}

# Run a Docker Compose service
function dcr-fn {
	docker compose run $@
}

# Stop and remove a Docker container
function dsr-fn {
	docker stop $1;docker rm $1
}

# Remove all exited Docker containers
function drmc-fn {
       docker rm $(docker ps --all -q -f status=exited)
}

# Remove dangling Docker images
function drmid-fn {
       imgs=$(docker images -q -f dangling=true)
       [ ! -z "$imgs" ] && docker rmi "$imgs" || echo "no dangling images."
}

# Find Docker container IDs by label
# Supports expressions such as dex $(dlab label) sh
function dlab {
       docker ps --filter="label=$1" --format="{{.ID}}"
}

# Run Docker Compose commands
function dc-fn {
        docker compose $*
}

# Run the AWS CLI in a Docker container
function d-aws-cli-fn {
    docker run \
           -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
           -e AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION \
           -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
           amazon/aws-cli:latest $1 $2 $3
}

# Run the AWS CLI in Docker
alias daws=d-aws-cli-fn

# Run Docker Compose commands
alias dc=dc-fn

# Start Docker Compose services in the background
alias dcu="docker compose up -d"

# Stop and remove Docker Compose services
alias dcd="docker compose down"

# Run a Docker Compose service
alias dcr=dcr-fn

# Open a shell in a running Docker container
alias dex=dex-fn

# Inspect a Docker container or image
alias di=di-fn

# List Docker images
alias dim="docker images"

# List IP addresses of running Docker containers
alias dip=dip-fn

# Follow logs from a Docker container
alias dl=dl-fn

# List names of running Docker containers
alias dnames=dnames-fn

# List running Docker containers
alias dps="docker ps"

# List all Docker containers
alias dpsa="docker ps -a"

# Remove all exited Docker containers
alias drmc=drmc-fn

# Remove dangling Docker images
alias drmid=drmid-fn

# Run a new Docker container interactively
alias drun=drun-fn

# Remove unused Docker resources and images
alias dsp="docker system prune --all"

# Stop and remove a Docker container
alias dsr=dsr-fn
