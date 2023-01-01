#!/bin/bash

function main() {
    romName=${1}
	rootPath=`pwd`
	config_ini=${rootPath}/files/config/config.ini
	rm -rf out
	mkdir out
    echo -e "$(date "+%m/%d %H:%M:%S") ${romName} 正在解压刷机包"
	unzip -o ${romName} -d out

    cd out
    mkdir images
	rm -rf META-INF apex_info.pb care_map.pb payload_properties.txt
    echo -e "$(date "+%m/%d %H:%M:%S") 正在解压 payload.bin"
    ${rootPath}/bin/payload-dumper-go -o ${rootPath}/out/images payload.bin
    rm -rf payload.bin

	#cust分区
	[ -f images/cust.img ] && cust_patch || cust_mv

	#解包IMG
	unpackimg system
	unpackimg vendor
	unpackimg product
    #vbmeta
    vbmeta
	#Boot Patch
    magisk_boot
	#VAB
	patch_vab
	#System
	system_patch
	#打包IMG
	repackimg system
	repackimg vendor
	repackimg product

	mv images/system_ext.img system_ext.img
	mv images/odm.img odm.img
	super

	echo -e "$(date "+%m/%d %H:%M:%S") 正在生成Rom"
	sudo rm -rf _pycache_ system vendor product system.img vendor.img product.img system_ext.img odm.img
	cp -rf ${rootPath}/files/META-INF ${rootPath}/out/META-INF
	sudo zip -q -r rom.zip images META-INF
	echo -e "$(date "+%m/%d %H:%M:%S") 项目运行结束"
}

function unpackimg(){
	### 解包镜像
	mv images/${1}.img ${1}.img
	echo -e "$(date "+%m/%d %H:%M:%S") 正在解压 ${1}.img"
	sudo python3 ${rootPath}/bin/imgextractor.py ${1}.img ${1}
	rm -rf ${1}.img
	echo -e "$(date "+%m/%d %H:%M:%S") 解压 ${1}.img 完成"
}

function repackimg(){
	### 打包 ext4
	name=${1}
	mount_path="/$name"
	fileContexts="${rootPath}/out/${name}/config/${name}_file_contexts"
	fsConfig="${rootPath}/out/${name}/config/${name}_fs_config"
	imgSize=`echo "$(sudo du -sb ${rootPath}/out/${name} | awk {'print $1'}) + 104857600" | bc`
	outImg="${rootPath}/out/${name}.img"
	inFiles="${rootPath}/out/${name}/${name}"
	echo -e "$(date "+%m/%d %H:%M:%S") 正在打包 ${1}.img"
	sudo ${rootPath}/bin/make_ext4fs -J -T 1640966400 -S $fileContexts -l $imgSize -C $fsConfig -L $name -a $name $outImg $inFiles
	echo -e "$(date "+%m/%d %H:%M:%S") 打包 ${1}.img 完成"
}

function super(){
	### 打包 super
	echo -e "$(date "+%m/%d %H:%M:%S") 开始打包 super.img"
	superSize="$(cat ${config_ini} | grep "supers=" | awk -F '=' '{print $1}' )"
	sudo ${rootPath}/bin/lpmake --metadata-size 65536 --super-name super --device super:${superSize} --group main_a:${superSize} --group main_b:${superSize} --metadata-slots 3 --virtual-ab --partition system_a:readonly:$(echo $(stat -c "%s" system.img) | bc):main_a --image system_a=system.img --partition system_b:readonly:0:main_b --partition vendor_a:readonly:$(echo $(stat -c "%s" vendor.img) | bc):main_a --image vendor_a=vendor.img --partition vendor_b:readonly:0:main_b --partition product_a:readonly:$(echo $(stat -c "%s" product.img) | bc):main_a --image product_a=product.img --partition product_b:readonly:0:main_b --partition system_ext_a:readonly:$(echo $(stat -c "%s" system_ext.img) | bc):main_a --image system_ext_a=system_ext.img --partition system_ext_b:readonly:0:main_b --partition odm_a:readonly:$(echo $(stat -c "%s" odm.img) | bc):main_a --image odm_a=odm.img --partition odm_b:readonly:0:main_b --sparse --output images/super.img
	echo -e "$(date "+%m/%d %H:%M:%S") 打包 super.img 完成"
}

function vbmeta(){
	echo -e "$(date "+%m/%d %H:%M:%S") 正在去除 vbmeta 验证"
	mv ${rootPath}/out/images/vbmeta.img vbmeta.img
	mv ${rootPath}/out/images/vbmeta_system.img vbmeta_system.img

	#计算偏移量
	#AVB=`od -w16 -An -tx1 "*.img" | grep -i -B 2 '61 76 62 74 6f 6f 6c 20' | tr -d '[:space:]' | egrep -oi '000000..00000000617662746F6F6C20'`
	# 00000000000000000000000300000000617662746f6f6c20 "3, AVB Disabled."
	# 00000000000000000000000200000000617662746f6f6c20 "2, Boot Verification Disabled."
	# 00000000000000000000000100000000617662746f6f6c20 "1, Dm-verity Disabled."
	# 00000000000000000000000000000000617662746f6f6c20 "0, AVB Enabled."

	sudo ${rootPath}/bin/magiskboot hexpatch vbmeta.img 0000000000000000617662746F6F6C20 0000000200000000617662746F6F6C20
	sudo ${rootPath}/bin/magiskboot hexpatch vbmeta_system.img 0000000000000000617662746F6F6C20 0000000200000000617662746F6F6C20

	mv vbmeta.img ${rootPath}/out/images/vbmeta.img
	mv vbmeta_system.img ${rootPath}/out/images/vbmeta_system.img

	echo -e "$(date "+%m/%d %H:%M:%S") 去除 vbmeta 验证 完成"
}

function cust_patch() {
	echo -e "$(date "+%m/%d %H:%M:%S") 正在清理Cust分区，仅保留mipush相关配置文件"
	unpackimg cust
	sudo ls cust/cust/ | grep -v "cust_variant" | xargs rm -rf
	repackimg cust
	mv cust.img images/cust.img
	echo -e "$(date "+%m/%d %H:%M:%S") 清理Cust分区完成"
}

function cust_mv() {
	echo -e "$(date "+%m/%d %H:%M:%S") 未发现cust分区，替换相关文件"
	mv ${rootPath}/files/images/cust.img ${rootPath}/out/images/cust.img
	echo -e "$(date "+%m/%d %H:%M:%S") 替换分区完成"
}

function magisk_boot() {
    #修补Boot
    mv images/boot.img boot.img
	mv images/vendor_boot.img vendor_boot.img

	echo -e "$(date "+%m/%d %H:%M:%S") 正在使用 magisk 修补 boot"
	sudo ${rootPath}/bin/magiskboot unpack boot.img
	sudo ${rootPath}/bin/magiskboot cpio ramdisk.cpio patch
	for dt in dtb kernel_dtb extra; do
		[ -f $dt ] && sudo ${rootPath}/bin/magiskboot dtb $dt patch
	done
	sudo ${rootPath}/bin/magiskboot repack boot.img
	sudo rm -rf *kernel* *dtb* ramdisk.cpio*
	[ -f new-boot.img ] && mv new-boot.img images/boot.img
	sudo rm -rf new-boot.img boot.img
	echo -e "$(date "+%m/%d %H:%M:%S") magisk 修补 boot 完成"

    echo -e "$(date "+%m/%d %H:%M:%S") 正在使用 magisk 修补 vendor_boot"
	sudo ${rootPath}/bin/magiskboot unpack vendor_boot.img
	sudo ${rootPath}/bin/magiskboot cpio ramdisk.cpio patch
	for dt in dtb kernel_dtb extra; do
        [ -f $dt ] && sudo ${rootPath}/bin/magiskboot dtb $dt patch
	done
	sudo ${rootPath}/bin/magiskboot repack vendor_boot.img
	sudo rm -rf *kernel* *dtb* ramdisk.cpio*
	[ -f new-boot.img ] && mv new-boot.img images/vendor_boot.img
	sudo rm -rf new-boot.img vendor_boot.img
	echo -e "$(date "+%m/%d %H:%M:%S") magisk 修补 vendor_boot 完成"
}

function patch_vab() {
	echo -e "$(date "+%m/%d %H:%M:%S") 去除 fstab.qcom VAB相关"
	sudo sed -i 's/,avb_keys=\/avb\/q-gsi.avbpubkey:\/avb\/r-gsi.avbpubkey:\/avb\/s-gsi.avbpubkey//g' vendor/vendor/etc/fstab.qcom
	sudo sed -i 's/,avb=vbmeta_system//g' vendor/vendor/etc/fstab.qcom
	sudo sed -i 's/,avb//g' vendor/vendor/etc/fstab.qcom
	echo -e "$(date "+%m/%d %H:%M:%S") 修改 fstab.qcom 完成"
}

function system_patch() {
	echo -e "$(date "+%m/%d %H:%M:%S") 开始修补System"

	sudo sh -c "cat ${rootPath}/files/config/systemContextsAdd >> system/config/system_file_contexts"
	sudo sh -c "cat ${rootPath}/files/config/systemConfigAdd >> system/config/system_fs_config"
	# Magisk
	sudo mkdir system/system/system/data-app/Magisk
	sudo cp ${rootPath}/files/app/Magisk.apk system/system/system/data-app/Magisk/Magisk.apk

	#sudo cp -rf ${rootPath}/files/config/com.android.systemui system/system/system/media/theme/default/com.android.systemui

    # DC调光
	sudo sed -i 's/<bool name=\"support_dc_backlight\">false<\/bool>/<bool name=\"support_dc_backlight\">true<\/bool>/g' product/product/etc/device_features/*xml
	sudo sed -i 's/<bool name=\"support_secret_dc_backlight\">true<\/bool>/<bool name=\"support_secret_dc_backlight\">false<\/bool>/g' product/product/etc/device_features/*xml

	#删除lost+found
    #### product
	sudo sed -i '0,/[a-z]\+\/lost\\+found/{/[a-z]\+\/lost\\+found/d}' product/config/product_file_contexts
    #### vendor
	sudo sed -i '0,/[a-z]\+\/lost\\+found/{/[a-z]\+\/lost\\+found/d}' vendor/config/vendor_file_contexts
    #### system
    sudo sed -i '0,/[a-z]\+\/lost\\+found/{/[a-z]\+\/lost\\+found/d}' system/config/system_file_contexts

	Miui_Version="$(cat system/system/system/build.prop | grep "ro.build.version.incremental" | awk -F '=' '{print $2}' | awk -F '.' '{print $1}')"

	[[ ${Miui_Version} == "V14" ]] && miui14 || miui

	while read file
	do
		[[ ${file} =~ "#" ]] && continue;
		if [ -f "${file}" ] || [ -d "${file}" ]; 
		then
		echo -e "$(date "+%m/%d %H:%M:%S") Delete ${file}"
		sudo rm -rf "${file}"
		fi
	done < ${rootPath}/files/config/remove_list

	# app_list=(
	# 	# "${priv_app_path}/MIUIQuickSearchBox"
	# 	# "${data_app_path}/com.*"
	# 	# "${app_path}/Hybrid*"
    #   # "${p_data_app_path}/BaiduIME"
    # )

	# for file in ${app_list[*]}; do
	# 	echo -e "$(date "+%m/%d %H:%M:%S") Delete ${file}"
	# 	sudo rm -rf "${file}"
	# done

	echo -e "$(date "+%m/%d %H:%M:%S") 修改System 完成"
}

function miui14() {
	[[ $(cat ${config_ini} | grep "AnalyticsCore=" | awk -F '=' '{print $2}' ) == "true" ]] && sudo cp -rf ${rootPath}/files/app/AnalyticsCore.apk product/product/app/AnalyticsCore/AnalyticsCore.apk
	# theme
	sudo cp -rf ${rootPath}/files/config/com.android.settings product/product/media/theme/default/com.android.settings
}

function miui() {
	[[ $(cat ${config_ini} | grep "AnalyticsCore=" | awk -F '=' '{print $2}' ) == "true" ]] && sudo cp -rf ${rootPath}/files/app/AnalyticsCore.apk system/system/system/app/AnalyticsCore/AnalyticsCore.apk
	# theme
	sudo cp -rf ${rootPath}/files/config/com.android.settings system/system/system/media/theme/default/com.android.settings
}

main ${1}