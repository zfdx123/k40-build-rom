#!/bin/bash

function main() {
    romName=${1}
	rootPath=`pwd`
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

	#解包IMG
	unpackimg system
	unpackimg vendor
	unpackimg product
    #VAB
    vbmeta
	#Boot Patch
    magisk_boot
	#System
	system_patch
	#打包IMG
	repackimg system
	repackimg vendor
	repackimg product

	mv images/system_ext.img system_ext.img
	mv images/odm.img odm.img

	super

	sudo rm -rf _pycache_ system vendor product system.img vendor.img product.img system_ext.img odm.img
	cp -rf ${rootPath}/files/META-INF ${rootPath}/out/META-INF
	sudo zip -q -r rom.zip images META-INF
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
	sudo ${rootPath}/bin/lpmake --metadata-size 65536 --super-name super --device super:9126805504 --group main_a:9126805504 --group main_b:9126805504 --metadata-slots 3 --virtual-ab --partition system_a:readonly:$(echo $(stat -c "%s" system.img) | bc):main_a --image system_a=system.img --partition system_b:readonly:0:main_b --partition vendor_a:readonly:$(echo $(stat -c "%s" vendor.img) | bc):main_a --image vendor_a=vendor.img --partition vendor_b:readonly:0:main_b --partition product_a:readonly:$(echo $(stat -c "%s" product.img) | bc):main_a --image product_a=product.img --partition product_b:readonly:0:main_b --partition system_ext_a:readonly:$(echo $(stat -c "%s" system_ext.img) | bc):main_a --image system_ext_a=system_ext.img --partition system_ext_b:readonly:0:main_b --partition odm_a:readonly:$(echo $(stat -c "%s" odm.img) | bc):main_a --image odm_a=odm.img --partition odm_b:readonly:0:main_b --sparse --output images/super.img
	echo -e "$(date "+%m/%d %H:%M:%S") 打包 super.img 完成"
}

function vbmeta(){
	# 替换 vbmeta 镜像
	echo -e "$(date "+%m/%d %H:%M:%S") 正在去除 vbmeta 验证——————替换镜像"
	cp -rf ${rootPath}/files/images/vbmeta.img ${rootPath}/out/images/vbmeta.img
	cp -rf ${rootPath}/files/images/vbmeta_system.img ${rootPath}/out/images/vbmeta_system.img
	echo -e "$(date "+%m/%d %H:%M:%S") 正在去除 vbmeta 验证——————替换镜像——完成"
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
	[ -f new-boot.img ] && cp -rf new-boot.img ${rootPath}/out/images/boot.img
	sudo rm -rf new-boot.img
	echo -e "$(date "+%m/%d %H:%M:%S") magisk 修补 boot 完成"

    echo -e "$(date "+%m/%d %H:%M:%S") 正在使用 magisk 修补 vendor_boot"
	sudo ${rootPath}/bin/magiskboot unpack vendor_boot.img
	sudo ${rootPath}/bin/magiskboot cpio ramdisk.cpio patch
	for dt in dtb kernel_dtb extra; do
        [ -f $dt ] && sudo ${rootPath}/bin/magiskboot dtb $dt patch
	done
	sudo ${rootPath}/bin/magiskboot repack vendor_boot.img
	sudo rm -rf *kernel* *dtb* ramdisk.cpio*
	[ -f new-boot.img ] && cp -rf new-boot.img ${rootPath}/out/images/vendor_boot.img
	sudo rm -rf new-boot.img
	echo -e "$(date "+%m/%d %H:%M:%S") magisk 修补 vendor_boot 完成"
}

function system_patch() {
	echo -e "$(date "+%m/%d %H:%M:%S") 开始修补System"

	sudo sh -c "cat ${rootPath}/files/config/systemContextsAdd >> system/config/system_file_contexts"
	sudo sh -c "cat ${rootPath}/files/config/systemConfigAdd >> system/config/system_fs_config"
	# Magisk
	sudo mkdir system/system/system/data-app/Magisk
	sudo cp ${rootPath}/files/app/Magisk.apk system/system/system/data-app/Magisk/Magisk.apk

	# theme
	sudo cp -rf ${rootPath}/files/config/com.android.settings system/system/system/media/theme/default/com.android.settings
	#sudo cp -rf ${rootPath}/files/config/com.android.systemui system/system/system/media/theme/default/com.android.systemui

	# 去除 AVB
	sudo sed -i 's/,avb_keys=\/avb\/q-gsi.avbpubkey:\/avb\/r-gsi.avbpubkey:\/avb\/s-gsi.avbpubkey//g' vendor/vendor/etc/fstab.qcom
	sudo sed -i 's/,avb=vbmeta_system//g' vendor/vendor/etc/fstab.qcom
	sudo sed -i 's/,avb//g' vendor/vendor/etc/fstab.qcom

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

	#替换掉广告毒瘤
	sudo cp -rf ${rootPath}/files/app/AnalyticsCore.apk system/system/system/app/AnalyticsCore/AnalyticsCore.apk

    app_list=(
        "product/product/data-app/BaiduIME"
        "system/system/system/app/mab"
        "system/system/system/app/MSA"
        "system/system/system/app/Hybrid*"
		"system/system/system/app/SogouInput"
		"system/system/system/data-app/com.*"
		"system/system/system/data-app/MiDrive"
		"system/system/system/data-app/SmartHome"
		"system/system/system/data-app/MIUIYoupin"
		"system/system/system/data-app/MIUINewHome"
		"system/system/system/data-app/MIUIVipAccount"
		"system/system/system/data-app/MIUIDuokanReader"
		"system/system/system/priv-app/MIUIQuickSearchBox"
    )

	for file in ${app_list[*]}; do
		echo -e "$(date "+%m/%d %H:%M:%S") Delete ${file}"
		sudo rm -rf "${file}"
	done

	echo -e "$(date "+%m/%d %H:%M:%S") 修改System 完成"

}

main ${1}