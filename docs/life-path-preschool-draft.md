# Life Path — Preschool stage draft (for review)

**Status:** **Implemented** in `life_path_en_v1.json` / `life_path_zh_v1.json` (stage `preschool`, 299 pairs). This doc remains the review source of truth for content.

## Where current words live

| Asset | Path | Stages | Count |
|-------|------|--------|------:|
| English | `Sources/LifePath/life_path_en_v1.json` | baby, toddler | 50 + 66 = **116** |
| Chinese | `Sources/LifePath/life_path_zh_v1.json` | baby, toddler | 50 + 63 = **113** |
| Manifest | `Sources/LifePath/life_path_manifest.json` | — | entryCount above |
| Stage plan | `docs/life-path-vocab-stages.md` §4 | plans `preschool` ~250 | not implemented |

There are **no** `"stageId": "preschool"` entries yet.

## Design target

- **Stage ID:** `preschool` · **Display:** Preschool / 学前
- **Focus:** daily life + school readiness (~ages 3–5)
- **Plan size:** ~250 · **This draft:** **299** parallel EN↔ZH pairs
- Rules: no overlap with baby/toddler fronts; Chinese 词-first + pinyin; multi-tag OK

## Theme breakdown

| Theme | Count |
|-------|------:|
| School & classroom | 35 |
| People | 18 |
| Daily routine & time | 28 |
| Emotion | 12 |
| Body | 14 |
| Food | 30 |
| Animals | 18 |
| Home & community | 28 |
| Nature & weather | 20 |
| Clothing | 12 |
| Numbers & colors | 18 |
| Descriptors & places | 31 |
| More actions | 35 |
| **Total** | **299** |

Tag frequency (entries may have multiple tags):

- `actions`: 60
- `school`: 38
- `food`: 34
- `descriptors`: 34
- `locations`: 23
- `people`: 20
- `home`: 20
- `animals`: 18
- `numbers_colors`: 18
- `emotion`: 16
- `body`: 15
- `social`: 14
- `clothing`: 13
- `toys_play`: 11
- `time`: 11
- `nature`: 11
- `weather`: 10

## Full draft

| # | Theme | English | Chinese | Pinyin | Tags |
|--:|-------|---------|---------|--------|------|
| 1 | School & classroom | teacher | 老师 | lǎoshī | people, school |
| 2 | School & classroom | friend | 朋友 | péngyou | people, social |
| 3 | School & classroom | school | 学校 | xuéxiào | locations, school |
| 4 | School & classroom | classroom | 教室 | jiàoshì | locations, school |
| 5 | School & classroom | bag | 书包 | shūbāo | school |
| 6 | School & classroom | pencil | 铅笔 | qiānbǐ | school |
| 7 | School & classroom | crayon | 蜡笔 | làbǐ | school, toys_play |
| 8 | School & classroom | paper | 纸 | zhǐ | school |
| 9 | School & classroom | eraser | 橡皮 | xiàngpí | school |
| 10 | School & classroom | scissors | 剪刀 | jiǎndāo | school |
| 11 | School & classroom | glue | 胶水 | jiāoshuǐ | school |
| 12 | School & classroom | story | 故事 | gùshi | school |
| 13 | School & classroom | song | 歌 | gē | school |
| 14 | School & classroom | picture | 图画 | túhuà | school |
| 15 | School & classroom | draw | 画 | huà | actions, school |
| 16 | School & classroom | write | 写 | xiě | actions, school |
| 17 | School & classroom | read | 读 | dú | actions, school |
| 18 | School & classroom | count | 数 | shǔ | actions, school |
| 19 | School & classroom | listen | 听 | tīng | actions, school |
| 20 | School & classroom | speak | 说 | shuō | actions, school |
| 21 | School & classroom | sing | 唱 | chàng | actions, school |
| 22 | School & classroom | dance | 跳舞 | tiàowǔ | actions |
| 23 | School & classroom | learn | 学习 | xuéxí | actions, school |
| 24 | School & classroom | share | 分享 | fēnxiǎng | actions, social |
| 25 | School & classroom | line up | 排队 | páiduì | actions, school |
| 26 | School & classroom | raise hand | 举手 | jǔ shǒu | actions, school |
| 27 | School & classroom | snack | 点心 | diǎnxin | food, school |
| 28 | School & classroom | nap | 午睡 | wǔshuì | actions, school |
| 29 | School & classroom | homework | 作业 | zuòyè | school |
| 30 | School & classroom | desk | 课桌 | kèzhuō | school |
| 31 | School & classroom | board | 黑板 | hēibǎn | school |
| 32 | School & classroom | cut | 剪 | jiǎn | actions, school |
| 33 | School & classroom | paste | 贴 | tiē | actions, school |
| 34 | School & classroom | color | 涂色 | tú sè | actions, school |
| 35 | School & classroom | rule | 规则 | guīzé | school, social |
| 36 | People | brother | 哥哥 | gēge | people |
| 37 | People | sister | 姐姐 | jiějie | people |
| 38 | People | younger brother | 弟弟 | dìdi | people |
| 39 | People | younger sister | 妹妹 | mèimei | people |
| 40 | People | uncle | 叔叔 | shūshu | people |
| 41 | People | aunt | 阿姨 | āyí | people |
| 42 | People | boy | 男孩 | nánhái | people |
| 43 | People | girl | 女孩 | nǚhái | people |
| 44 | People | doctor | 医生 | yīshēng | people |
| 45 | People | nurse | 护士 | hùshi | people |
| 46 | People | driver | 司机 | sījī | people |
| 47 | People | police | 警察 | jǐngchá | people |
| 48 | People | name | 名字 | míngzi | people, social |
| 49 | People | me | 我 | wǒ | people |
| 50 | People | you | 你 | nǐ | people |
| 51 | People | we | 我们 | wǒmen | people |
| 52 | People | he | 他 | tā | people |
| 53 | People | she | 她 | tā | people |
| 54 | Daily routine & time | morning | 早上 | zǎoshang | time |
| 55 | Daily routine & time | afternoon | 下午 | xiàwǔ | time |
| 56 | Daily routine & time | evening | 晚上 | wǎnshang | time |
| 57 | Daily routine & time | night | 夜里 | yèli | time |
| 58 | Daily routine & time | today | 今天 | jīntiān | time |
| 59 | Daily routine & time | tomorrow | 明天 | míngtiān | time |
| 60 | Daily routine & time | yesterday | 昨天 | zuótiān | time |
| 61 | Daily routine & time | now | 现在 | xiànzài | time |
| 62 | Daily routine & time | later | 等一下 | děng yīxià | time, social |
| 63 | Daily routine & time | birthday | 生日 | shēngrì | time, social |
| 64 | Daily routine & time | wake up | 起床 | qǐchuáng | actions |
| 65 | Daily routine & time | get dressed | 穿衣服 | chuān yīfu | actions, clothing |
| 66 | Daily routine & time | brush teeth | 刷牙 | shuā yá | actions, body |
| 67 | Daily routine & time | breakfast | 早餐 | zǎocān | food |
| 68 | Daily routine & time | lunch | 午餐 | wǔcān | food |
| 69 | Daily routine & time | dinner | 晚餐 | wǎncān | food |
| 70 | Daily routine & time | ready | 准备好 | zhǔnbèi hǎo | descriptors |
| 71 | Daily routine & time | wait | 等 | děng | actions, social |
| 72 | Daily routine & time | hurry | 快点 | kuài diǎn | actions, social |
| 73 | Daily routine & time | rest | 休息 | xiūxi | actions |
| 74 | Daily routine & time | finish | 完成 | wánchéng | actions |
| 75 | Daily routine & time | start | 开始 | kāishǐ | actions |
| 76 | Daily routine & time | try | 试试 | shìshi | actions |
| 77 | Daily routine & time | good morning | 早上好 | zǎoshang hǎo | social |
| 78 | Daily routine & time | good night | 晚安 | wǎn'ān | social |
| 79 | Daily routine & time | you're welcome | 不客气 | bú kèqi | social |
| 80 | Daily routine & time | excuse me | 不好意思 | bù hǎoyìsi | social |
| 81 | Daily routine & time | together | 一起 | yīqǐ | social, descriptors |
| 82 | Emotion | angry | 生气 | shēngqì | emotion |
| 83 | Emotion | scared | 害怕 | hàipà | emotion |
| 84 | Emotion | tired | 累 | lèi | emotion, body |
| 85 | Emotion | excited | 兴奋 | xīngfèn | emotion |
| 86 | Emotion | brave | 勇敢 | yǒnggǎn | emotion |
| 87 | Emotion | shy | 害羞 | hàixiū | emotion |
| 88 | Emotion | worried | 担心 | dānxīn | emotion |
| 89 | Emotion | fun | 好玩 | hǎowán | emotion, descriptors |
| 90 | Emotion | funny | 有趣 | yǒuqù | emotion, descriptors |
| 91 | Emotion | proud | 骄傲 | jiāo'ào | emotion |
| 92 | Emotion | bored | 无聊 | wúliáo | emotion |
| 93 | Emotion | surprised | 惊讶 | jīngyà | emotion |
| 94 | Body | hair | 头发 | tóufa | body |
| 95 | Body | face | 脸 | liǎn | body |
| 96 | Body | tooth | 牙齿 | yáchǐ | body |
| 97 | Body | neck | 脖子 | bózi | body |
| 98 | Body | arm | 胳膊 | gēbo | body |
| 99 | Body | finger | 手指 | shǒuzhǐ | body |
| 100 | Body | leg | 腿 | tuǐ | body |
| 101 | Body | knee | 膝盖 | xīgài | body |
| 102 | Body | tummy | 肚子 | dùzi | body |
| 103 | Body | back | 背 | bèi | body |
| 104 | Body | sick | 生病 | shēngbìng | body |
| 105 | Body | hurt | 受伤 | shòushāng | body |
| 106 | Body | medicine | 药 | yào | body, home |
| 107 | Body | careful | 小心 | xiǎoxīn | social, descriptors |
| 108 | Food | orange | 橙子 | chéngzi | food |
| 109 | Food | grape | 葡萄 | pútao | food |
| 110 | Food | strawberry | 草莓 | cǎoméi | food |
| 111 | Food | watermelon | 西瓜 | xīguā | food |
| 112 | Food | pear | 梨 | lí | food |
| 113 | Food | vegetable | 蔬菜 | shūcài | food |
| 114 | Food | carrot | 胡萝卜 | húluóbo | food |
| 115 | Food | potato | 土豆 | tǔdòu | food |
| 116 | Food | tomato | 西红柿 | xīhóngshì | food |
| 117 | Food | corn | 玉米 | yùmǐ | food |
| 118 | Food | noodles | 面条 | miàntiáo | food |
| 119 | Food | soup | 汤 | tāng | food |
| 120 | Food | meat | 肉 | ròu | food |
| 121 | Food | tofu | 豆腐 | dòufu | food |
| 122 | Food | yogurt | 酸奶 | suānnǎi | food |
| 123 | Food | ice cream | 冰淇淋 | bīngqílín | food |
| 124 | Food | cake | 蛋糕 | dàngāo | food |
| 125 | Food | candy | 糖 | táng | food |
| 126 | Food | tea | 茶 | chá | food |
| 127 | Food | spoon | 勺子 | sháozi | food, home |
| 128 | Food | chopsticks | 筷子 | kuàizi | food, home |
| 129 | Food | bowl | 碗 | wǎn | food, home |
| 130 | Food | plate | 盘子 | pánzi | food, home |
| 131 | Food | cup | 杯子 | bēizi | food, home |
| 132 | Food | fork | 叉子 | chāzi | food, home |
| 133 | Food | yummy | 好吃 | hǎochī | food, descriptors |
| 134 | Food | sweet | 甜 | tián | food, descriptors |
| 135 | Food | spicy | 辣 | là | food, descriptors |
| 136 | Food | salt | 盐 | yán | food |
| 137 | Food | sandwich | 三明治 | sānmíngzhì | food |
| 138 | Animals | pig | 猪 | zhū | animals |
| 139 | Animals | sheep | 羊 | yáng | animals |
| 140 | Animals | rabbit | 兔子 | tùzi | animals |
| 141 | Animals | mouse | 老鼠 | lǎoshǔ | animals |
| 142 | Animals | frog | 青蛙 | qīngwā | animals |
| 143 | Animals | bear | 熊 | xióng | animals |
| 144 | Animals | lion | 狮子 | shīzi | animals |
| 145 | Animals | tiger | 老虎 | lǎohǔ | animals |
| 146 | Animals | elephant | 大象 | dàxiàng | animals |
| 147 | Animals | monkey | 猴子 | hóuzi | animals |
| 148 | Animals | panda | 熊猫 | xióngmāo | animals |
| 149 | Animals | butterfly | 蝴蝶 | húdié | animals |
| 150 | Animals | bee | 蜜蜂 | mìfēng | animals |
| 151 | Animals | ant | 蚂蚁 | mǎyǐ | animals |
| 152 | Animals | chick | 小鸡 | xiǎo jī | animals |
| 153 | Animals | pet | 宠物 | chǒngwù | animals |
| 154 | Animals | zoo | 动物园 | dòngwùyuán | locations, animals |
| 155 | Animals | farm | 农场 | nóngchǎng | locations, animals |
| 156 | Home & community | house | 房子 | fángzi | home, locations |
| 157 | Home & community | home | 家 | jiā | home, locations |
| 158 | Home & community | room | 房间 | fángjiān | home |
| 159 | Home & community | kitchen | 厨房 | chúfáng | home |
| 160 | Home & community | bathroom | 卫生间 | wèishēngjiān | home |
| 161 | Home & community | window | 窗户 | chuānghu | home |
| 162 | Home & community | floor | 地板 | dìbǎn | home |
| 163 | Home & community | light | 灯 | dēng | home |
| 164 | Home & community | key | 钥匙 | yàoshi | home |
| 165 | Home & community | clock | 钟 | zhōng | home, time |
| 166 | Home & community | TV | 电视 | diànshì | home |
| 167 | Home & community | computer | 电脑 | diànnǎo | home, school |
| 168 | Home & community | toy | 玩具 | wánjù | toys_play |
| 169 | Home & community | block | 积木 | jīmù | toys_play |
| 170 | Home & community | puzzle | 拼图 | pīntú | toys_play |
| 171 | Home & community | doll | 娃娃 | wáwa | toys_play |
| 172 | Home & community | balloon | 气球 | qìqiú | toys_play |
| 173 | Home & community | bike | 自行车 | zìxíngchē | toys_play |
| 174 | Home & community | swing | 秋千 | qiūqiān | toys_play |
| 175 | Home & community | slide | 滑梯 | huátī | toys_play |
| 176 | Home & community | park | 公园 | gōngyuán | locations |
| 177 | Home & community | store | 商店 | shāngdiàn | locations |
| 178 | Home & community | hospital | 医院 | yīyuàn | locations |
| 179 | Home & community | library | 图书馆 | túshūguǎn | locations, school |
| 180 | Home & community | playground | 游乐场 | yóulèchǎng | locations |
| 181 | Home & community | bus | 公共汽车 | gōnggòng qìchē | locations |
| 182 | Home & community | train | 火车 | huǒchē | locations |
| 183 | Home & community | plane | 飞机 | fēijī | locations |
| 184 | Nature & weather | sun | 太阳 | tàiyáng | nature |
| 185 | Nature & weather | moon | 月亮 | yuèliang | nature |
| 186 | Nature & weather | star | 星星 | xīngxing | nature |
| 187 | Nature & weather | sky | 天空 | tiānkōng | nature |
| 188 | Nature & weather | cloud | 云 | yún | weather |
| 189 | Nature & weather | rain | 雨 | yǔ | weather |
| 190 | Nature & weather | snow | 雪 | xuě | weather |
| 191 | Nature & weather | wind | 风 | fēng | weather |
| 192 | Nature & weather | rainbow | 彩虹 | cǎihóng | weather |
| 193 | Nature & weather | tree | 树 | shù | nature |
| 194 | Nature & weather | flower | 花 | huā | nature |
| 195 | Nature & weather | grass | 草 | cǎo | nature |
| 196 | Nature & weather | leaf | 叶子 | yèzi | nature |
| 197 | Nature & weather | sea | 海 | hǎi | nature |
| 198 | Nature & weather | river | 河 | hé | nature |
| 199 | Nature & weather | mountain | 山 | shān | nature |
| 200 | Nature & weather | weather | 天气 | tiānqì | weather |
| 201 | Nature & weather | sunny | 晴天 | qíngtiān | weather |
| 202 | Nature & weather | warm | 暖和 | nuǎnhuo | weather, descriptors |
| 203 | Nature & weather | cool | 凉快 | liángkuai | weather, descriptors |
| 204 | Clothing | dress | 裙子 | qúnzi | clothing |
| 205 | Clothing | jacket | 夹克 | jiákè | clothing |
| 206 | Clothing | sweater | 毛衣 | máoyī | clothing |
| 207 | Clothing | gloves | 手套 | shǒutào | clothing |
| 208 | Clothing | scarf | 围巾 | wéijīn | clothing |
| 209 | Clothing | pajamas | 睡衣 | shuìyī | clothing |
| 210 | Clothing | boots | 靴子 | xuēzi | clothing |
| 211 | Clothing | backpack | 背包 | bēibāo | clothing, school |
| 212 | Clothing | umbrella | 雨伞 | yǔsǎn | clothing, weather |
| 213 | Clothing | glasses | 眼镜 | yǎnjìng | clothing |
| 214 | Clothing | button | 扣子 | kòuzi | clothing |
| 215 | Clothing | zipper | 拉链 | lāliàn | clothing |
| 216 | Numbers & colors | four | 四 | sì | numbers_colors |
| 217 | Numbers & colors | five | 五 | wǔ | numbers_colors |
| 218 | Numbers & colors | six | 六 | liù | numbers_colors |
| 219 | Numbers & colors | seven | 七 | qī | numbers_colors |
| 220 | Numbers & colors | eight | 八 | bā | numbers_colors |
| 221 | Numbers & colors | nine | 九 | jiǔ | numbers_colors |
| 222 | Numbers & colors | ten | 十 | shí | numbers_colors |
| 223 | Numbers & colors | green | 绿 | lǜ | numbers_colors |
| 224 | Numbers & colors | yellow | 黄 | huáng | numbers_colors |
| 225 | Numbers & colors | purple | 紫 | zǐ | numbers_colors |
| 226 | Numbers & colors | pink | 粉红 | fěnhóng | numbers_colors |
| 227 | Numbers & colors | brown | 棕 | zōng | numbers_colors |
| 228 | Numbers & colors | black | 黑 | hēi | numbers_colors |
| 229 | Numbers & colors | white | 白 | bái | numbers_colors |
| 230 | Numbers & colors | many | 很多 | hěn duō | numbers_colors, descriptors |
| 231 | Numbers & colors | all | 全部 | quánbù | numbers_colors, descriptors |
| 232 | Numbers & colors | first | 第一 | dì yī | numbers_colors |
| 233 | Numbers & colors | half | 一半 | yī bàn | numbers_colors |
| 234 | Descriptors & places | fast | 快 | kuài | descriptors |
| 235 | Descriptors & places | slow | 慢 | màn | descriptors |
| 236 | Descriptors & places | tall | 高 | gāo | descriptors |
| 237 | Descriptors & places | short | 矮 | ǎi | descriptors |
| 238 | Descriptors & places | long | 长 | cháng | descriptors |
| 239 | Descriptors & places | soft | 软 | ruǎn | descriptors |
| 240 | Descriptors & places | hard | 硬 | yìng | descriptors |
| 241 | Descriptors & places | loud | 大声 | dà shēng | descriptors |
| 242 | Descriptors & places | quiet | 安静 | ānjìng | descriptors |
| 243 | Descriptors & places | wet | 湿 | shī | descriptors |
| 244 | Descriptors & places | dry | 干 | gān | descriptors |
| 245 | Descriptors & places | full | 满 | mǎn | descriptors |
| 246 | Descriptors & places | empty | 空 | kōng | descriptors |
| 247 | Descriptors & places | new | 新 | xīn | descriptors |
| 248 | Descriptors & places | old | 旧 | jiù | descriptors |
| 249 | Descriptors & places | same | 一样 | yīyàng | descriptors |
| 250 | Descriptors & places | different | 不同 | bù tóng | descriptors |
| 251 | Descriptors & places | pretty | 漂亮 | piàoliang | descriptors |
| 252 | Descriptors & places | easy | 容易 | róngyì | descriptors |
| 253 | Descriptors & places | difficult | 难 | nán | descriptors |
| 254 | Descriptors & places | right | 对 | duì | descriptors, school |
| 255 | Descriptors & places | wrong | 错 | cuò | descriptors, school |
| 256 | Descriptors & places | left | 左 | zuǒ | locations |
| 257 | Descriptors & places | right side | 右 | yòu | locations |
| 258 | Descriptors & places | front | 前面 | qiánmiàn | locations |
| 259 | Descriptors & places | behind | 后面 | hòumiàn | locations |
| 260 | Descriptors & places | beside | 旁边 | pángbiān | locations |
| 261 | Descriptors & places | inside | 里面 | lǐmiàn | locations |
| 262 | Descriptors & places | outside | 外面 | wàimiàn | locations |
| 263 | Descriptors & places | near | 近 | jìn | locations |
| 264 | Descriptors & places | far | 远 | yuǎn | locations |
| 265 | More actions | close | 关闭 | guānbì | actions |
| 266 | More actions | hold | 握 | wò | actions |
| 267 | More actions | carry | 搬 | bān | actions |
| 268 | More actions | bring | 带来 | dài lái | actions |
| 269 | More actions | show | 给看 | gěi kàn | actions |
| 270 | More actions | tell | 告诉 | gàosu | actions |
| 271 | More actions | ask | 问 | wèn | actions |
| 272 | More actions | answer | 回答 | huídá | actions, school |
| 273 | More actions | make | 做 | zuò | actions |
| 274 | More actions | build | 搭建 | dājiàn | actions, toys_play |
| 275 | More actions | break | 弄坏 | nòng huài | actions |
| 276 | More actions | fix | 修理 | xiūlǐ | actions |
| 277 | More actions | use | 用 | yòng | actions |
| 278 | More actions | need | 需要 | xūyào | actions |
| 279 | More actions | like | 喜欢 | xǐhuan | actions, emotion |
| 280 | More actions | know | 知道 | zhīdào | actions |
| 281 | More actions | think | 想 | xiǎng | actions |
| 282 | More actions | smell | 闻 | wén | actions |
| 283 | More actions | touch | 摸 | mō | actions |
| 284 | More actions | hear | 听见 | tīngjiàn | actions |
| 285 | More actions | swim | 游泳 | yóuyǒng | actions |
| 286 | More actions | ride | 骑 | qí | actions |
| 287 | More actions | fly | 飞 | fēi | actions |
| 288 | More actions | buy | 买 | mǎi | actions |
| 289 | More actions | clean up | 收拾 | shōushi | actions, home |
| 290 | More actions | hide | 藏 | cáng | actions, toys_play |
| 291 | More actions | laugh | 笑 | xiào | actions, emotion |
| 292 | More actions | cry | 哭 | kū | actions, emotion |
| 293 | More actions | smile | 微笑 | wēixiào | actions, emotion |
| 294 | More actions | leave | 离开 | líkāi | actions |
| 295 | More actions | return | 回来 | huílai | actions |
| 296 | More actions | stay | 留下 | liú xià | actions |
| 297 | More actions | follow | 跟着 | gēnzhe | actions |
| 298 | More actions | choose | 选择 | xuǎnzé | actions |
| 299 | More actions | remember | 记住 | jìzhù | actions |

## Proposed stage metadata (after approval)

```json
{
  "id": "preschool",
  "order": 2,
  "title": {
    "en": "Preschool",
    "zh": "学前"
  },
  "subtitle": {
    "en": "Daily life & school",
    "zh": "日常生活与学前"
  },
  "targetCount": 299,
  "clearReward": {
    "xp": 200,
    "coins": 100
  }
}
```

IDs after merge: `en_preschool_001`… / `zh_preschool_001`…

## Review questions

1. **Size** — keep ~299, trim toward 200, or grow to 250 exactly?
2. **Phrases** — OK: `good morning`, `brush teeth`, `line up`, `you're welcome`, `right side`?
3. **Pronouns** — keep `me/you/we/he/she`?
4. **Kinship** — older + younger siblings included
5. **Medical light** — `sick`, `hurt`, `medicine` (no blood / underwear)
6. **Disambiguation** — `right` = 对; `right side` = 右

Reply with cuts/edits by **#** or theme. Then we merge into the Life Path JSONs + manifest + tests.

Also: `docs/life-path-preschool-draft.json` (machine-readable).
