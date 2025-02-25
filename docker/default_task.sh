#!/bin/sh
set -e

# bot更新了新功能的话只需要重启容器就完成更新
function initPythonEnv() {
  echo "开始安装运行jd_bot需要的python环境及依赖..."
  # py3-multidict py3-yarl 为aiogram需要依赖的pip，但是alpine配置gcc编译环境才能安装这两个包，有点浪费，所以直接使用alpine提供的版本
  # 注释一下省的自己忘了为什么
  apk add --update python3-dev py3-pip py3-multidict py3-yarl
  echo "开始安装jd_bot依赖..."
  #测试
  #cd /jd_docker/docker/bot
  #合并
  cd "$ASM_DIR/scripts/docker/bot"
  pip3 install --upgrade pip
  pip3 install -r requirements.txt
  python3 setup.py install
}

#获取配置的自定义参数，
if [ $1 ]; then
  echo "容器启动，补充安装一些系统组件包..."
  #如果$1有值说明是容器启动调用的 执行配置系统以来包安装和id_rsa配置以及clone仓库的操作
  apk --no-cache add -f coreutils moreutils nodejs npm wget curl nano perl openssl openssh-client libav-tools libjpeg-turbo-dev libpng-dev libtool libgomp tesseract-ocr graphicsmagick
  echo "npm更换为淘宝镜像源"
  npm config set registry https://registry.npm.taobao.org
  echo "配置仓库更新密钥..."
  mkdir -p /root/.ssh
  echo -e ${KEY} >/root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  ssh-keyscan github.com >/root/.ssh/known_hosts
  echo "容器启动，拉取脚本仓库代码..."
  if [ -f "${ASM_DIR}/scripts/AutoSignMachine.js" ]; then
    echo "仓库已经存在，跳过clone操作..."
  else
    if [  -d ${ASM_DIR}/tmp ];then
      rmdir ${ASM_DIR}/tmp
    fi
    git clone --no-checkout -b ${ASM_SCRIPTS_BRANCH} ${REPO_URL} ${ASM_DIR}/tmp
    mv ${ASM_DIR}/tmp/.git ${ASM_DIR}/scripts
    rmdir ${ASM_DIR}/tmp
  fi
fi
echo -e "--------------------------------------------------------------\n"
[ -f ${ASM_DIR}/scripts/package.json ] && PackageListOld=$(cat ${ASM_DIR}/scripts/package.json)
echo "git pull拉取最新代码..."
cd ${ASM_DIR}/scripts
git reset --hard HEAD
git fetch --all
git reset --hard origin/${ASM_SCRIPTS_BRANCH}
git checkout ${ASM_SCRIPTS_BRANCH}

echo "npm install 安装最新依赖"
if [ ! -d ${ASM_DIR}/scripts/node_modules ]; then
    echo -e "检测到首次部署, 运行 npm install...\n"
    npm install --loglevel error -s --prefix ${ASM_DIR}/scripts >/dev/null
else
  if [[ "${PackageListOld}" != "$(cat package.json)" ]]; then
    echo -e "检测到package.json有变化，运行 npm install...\n"
    npm install -s --prefix ${ASM_DIR}/scripts >/dev/null
  else
    echo -e "检测到package.json无变化，跳过...\n"
  fi
fi

#更新到了最新bot代码
#启动tg bot交互前置条件成立，开始安装配置环境
if [ "$1" == "True" ]; then
  initPythonEnv
fi

mergedListFile="${ASM_DIR}/scripts/config/merged_list_file.sh"
customTaskFile="${ASM_DIR}/scripts/config/custom_task.sh"
envFile="/root/.AutoSignMachine/.env"
echo "定时任务文件路径为 ${mergedListFile}"
echo '' >${mergedListFile}

if [ $ENABLE_52POJIE ]; then
  echo "10 13 * * * sleep \$((RANDOM % 120)); node ${ASM_DIR}/scripts/index.js 52pojie --htVD_2132_auth=${htVD_2132_auth} --htVD_2132_saltkey=${htVD_2132_saltkey} >> ${ASM_DIR}/logs/52pojie.log 2>&1 &" >>${mergedListFile}
else
  echo "未配置启用52pojie签到任务环境变量ENABLE_52POJIE，故不添加52pojie定时任务..."
fi

if [ $ENABLE_BILIBILI ]; then
  echo "*/30 7-22 * * * sleep \$((RANDOM % 120)); node ${ASM_DIR}/scripts/index.js bilibili --username ${BILIBILI_ACCOUNT} --password ${BILIBILI_PWD} >> ${ASM_DIR}/logs/bilibili.log 2>&1 &" >>${mergedListFile}
else
  echo "未配置启用bilibi签到任务环境变量ENABLE_BILIBILI，故不添加Bilibili定时任务..."
fi

if [ $ENABLE_IQIYI ]; then
  echo "*/30 7-22 * * * sleep \$((RANDOM % 120)); node ${ASM_DIR}/scripts/index.js iqiyi --P00001 ${P00001} --P00PRU ${P00PRU} --QC005 ${QC005}  --dfp ${dfp} >> ${ASM_DIR}/logs/iqiyi.log 2>&1 &" >>${mergedListFile}
else
  echo "未配置启用iqiyi签到任务环境变量ENABLE_IQIYI，故不添加iqiyi定时任务..."
fi

if [ $ENABLE_UNICOM ]; then
  if [ -f $envFile ]; then
    cp -f $envFile ${ASM_DIR}/scripts/config/.env
    if [ $UNICOM_JOB_CONFIG ]; then
      echo "找到联通细分任务配置故拆分，针对每个任务增加定时任务"
      minute=0
      hour=8
      job_interval=6
      for job in $(paste -d" " -s - <$UNICOM_JOB_CONFIG); do
        echo "$minute $hour * * * node ${ASM_DIR}/scripts/index.js unicom --tryrun --tasks $job >>${ASM_DIR}/logs/unicom_$job.log 2>&1 &" >>${mergedListFile}
        minute=$(expr $minute + $job_interval)
        if [ $minute -ge 60 ]; then
          minute=0
          hour=$(expr $hour + 1)
        fi
      done
    else
      # echo "*/30 7-22 * * * sleep \$((RANDOM % 120)); node ${ASM_DIR}/scripts/index.js unicom >> ${ASM_DIR}/logs/unicom.log 2>&1 &" >>${mergedListFile}
      echo "*/30 7-22 * * * sleep \$((RANDOM % 120)); node ${ASM_DIR}/scripts/index.js unicom | tee -a ${ASM_DIR}/logs/unicom.log" >>${mergedListFile}
    fi
  else
    echo "未找到 .env配置文件，故不添加unicom定时任务。"
  fi
else
  echo "未配置启用unicom签到任务环境变量ENABLE_UNICOM，故不添加unicom定时任务..."
fi

echo "增加默认脚本更新任务..."
echo "21 */1 * * * entrypoint_less.sh >> ${ASM_DIR}/logs/default_task.log 2>&1" >>$mergedListFile

echo "追加自定义脚本任务..."
if [ ! -f $customTaskFile ]; then
  echo "未发现自定义脚本开始,创建新文件..."
  echo '' >$customTaskFile
fi

if [ -f $customTaskFile ]; then
  cat  $customTaskFile >>$mergedListFile
  echo "追加任务完成"
fi

# echo "判断是否配置自定义shell执行脚本..."
# if [ 0"$CUSTOM_SHELL_FILE" = "0" ]; then
#   echo "未配置自定shell脚本文件，跳过执行。"
# else
#   if expr "$CUSTOM_SHELL_FILE" : 'http.*' &>/dev/null; then
#     echo "自定义shell脚本为远程脚本，开始下在自定义远程脚本。"
#     wget -O /jds/shell_script_mod.sh $CUSTOM_SHELL_FILE
#     echo "下载完成，开始执行..."
#     echo "#远程自定义shell脚本追加定时任务" >>$mergedListFile
#     sh /jds/shell_script_mod.sh
#     echo "自定义远程shell脚本下载并执行结束。"
#   else
#     if [ ! -f $CUSTOM_SHELL_FILE ]; then
#       echo "自定义shell脚本为docker挂载脚本文件，但是指定挂载文件不存在，跳过执行。"
#     else
#       echo "docker挂载的自定shell脚本，开始执行..."
#       echo "#docker挂载自定义shell脚本追加定时任务" >>$mergedListFile
#       sh $CUSTOM_SHELL_FILE
#       echo "docker挂载的自定shell脚本，执行结束。"
#     fi
#   fi
# fi


echo "判断是否配置了随即延迟参数..."
if [ $RANDOM_DELAY_MAX ]; then
  if [ $RANDOM_DELAY_MAX -ge 1 ]; then
    echo "已设置随机延迟为 $RANDOM_DELAY_MAX , 设置延迟任务中..."
    sed -i "/node/sleep \$((RANDOM % \$RANDOM_DELAY_MAX)) && node/g" $mergedListFile
  fi
else
  echo "未配置随即延迟对应的环境变量，故不设置延迟任务..."
fi

echo "增加 |ts 任务日志输出时间戳..."
sed -i "/\( ts\| |ts\|| ts\)/!s/>>/\|ts >>/g" $mergedListFile

echo "加载最新的定时任务文件..."
crontab $mergedListFile
