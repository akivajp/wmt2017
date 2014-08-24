#!/bin/bash

KYTEA=/home/is/akiba-mi/usr/local/bin/kytea
KYTEA_ZH_DIC=/home/is/akiba-mi/usr/local/share/kytea/lcmc-0.4.0-1.mod
MOSES=/home/is/akiba-mi/exp/moses

IRSTLM=~/exp/irstlm
GIZA=~/usr/local/bin

#TRAIN_SIZE=40000
#TEST_SIZE=10000
#DEV_SIZE=5000

TRAIN_SIZE=4000
TEST_SIZE=1000
DEV_SIZE=500

echo "running script with PID: $$"

usage()
{
  echo "usage: $0 lang_id1 src1 lang_id2 src2 [test_size]"
}

show_exec()
{
  echo "[exec] $*"
  eval $*

  if [ $? -gt 0 ]
  then
    echo "[error]"
    exit 1
  fi
}

proc_args()
{
  ARGS=()
  OPTS=()

  while [ $# -gt 0 ]
  do
    arg=$1
    case $arg in
      --train_size=* )
        train_size=${arg#*=}
        ;;
      --test_size=* )
        test_size=${arg#*=}
        ;;
      --dev_size=* )
        dev_size=${arg#*=}
        ;;
      -* )
        OPTS+=($arg)
        ;;
      * )
        ARGS+=($arg)
        ;;
    esac

    shift
  done
}

tokenize()
{
  lang=$1
  prefix=$2
  src=${corpus}/${prefix}.${lang}
  output=${corpus}/${prefix}.tok.${lang}

  if [ $lang = "zh" ]
  then
    show_exec $KYTEA -notags -model $KYTEA_ZH_DIC \< ${src} \> ${output}
  else
    show_exec ~/exp/moses/scripts/tokenizer/tokenizer.perl -l $lang \< $src \> ${output}
  fi
}

train_truecaser()
{
  lang=$1
  prefix=$2
  src=${corpus}/${prefix}.tok.${lang}
  model=${corpus}/truecase-model.${lang}
  show_exec $MOSES/scripts/recaser/train-truecaser.perl --model ${model} --corpus ${src}
}

truecase()
{
  lang=$1
  prefix=$2
  show_exec $MOSES/scripts/recaser/truecase.perl --model ${corpus}/truecase-model.${lang} \< ${corpus}/${prefix}.tok.${lang} \> ${corpus}/${prefix}.true.${lang}
}

proc_args $*

if [ ${#ARGS[@]} -lt 4 ]
then
  usage
  exit 1
fi

lang1=${ARGS[0]}
src1=${ARGS[1]}
lang2=${ARGS[2]}
src2=${ARGS[3]}


declare -i train_size
if [ ! $train_size ]
then
  train_size=$TRAIN_SIZE
fi
if [ $train_size -lt 1 ]
then
  train_size=$TRAIN_SIZE
fi


declare -i test_size
if [ ! $test_size ]
then
  test_size=$TEST_SIZE
fi
if [ $test_size -lt 1 ]
then
  test_size=$TEST_SIZE
fi


declare -i dev_size
if [ ! $dev_size ]
then
  dev_size=$DEV_SIZE
fi
if [ $dev_size -lt 1 ]
then
  dev_size=$TEST_SIZE
fi


echo TRAIN_SIZE: $train_size
echo TEST_SIZE : $test_size
echo DEV_SIZE  : $dev_size

corpus=corpus_${lang1}-${lang2}
show_exec mkdir -p $corpus
show_exec head -${train_size} ${src1} \> $corpus/train.${lang1}
show_exec head -${train_size} ${src2} \> $corpus/train.${lang2}

#show_exec head -${test_size} $corpus/train.${lang1} \> $corpus/test.${lang1}
#show_exec head -${test_size} $corpus/train.${lang2} \> $corpus/test.${lang2}

show_exec head -${test_size} ${src1} \> $corpus/test.${lang1}
show_exec head -${test_size} ${src2} \> $corpus/test.${lang2}

#show_exec tail -n +${test_size} ${src1} \> $corpus/train.${lang1}
#show_exec tail -n +${test_size} ${src2} \> $corpus/train.${lang2}

show_exec head -${dev_size} ${src1} \> $corpus/dev.${lang1}
show_exec head -${dev_size} ${src2} \> $corpus/dev.${lang2}

tokenize ${lang1} train
tokenize ${lang2} train
tokenize ${lang1} test
tokenize ${lang2} test
tokenize ${lang1} dev
tokenize ${lang2} dev

train_truecaser ${lang1} train
train_truecaser ${lang2} train

truecase ${lang1} train
truecase ${lang2} train
truecase ${lang1} dev
truecase ${lang2} dev

show_exec ~/exp/moses/scripts/training/clean-corpus-n.perl $corpus/train.true ${lang1} ${lang2} $corpus/train.clean 1 80

