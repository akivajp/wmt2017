#!/bin/bash

NBEST=20
METHOD="counts"
LEX_METHOD="interpolate"

dir="$(cd "$(dirname "${BASH_SOURCE:-${(%):-%N}}")"; pwd)"
source "${dir}/common.sh"

echo "running script with PID: $$"

usage()
{
#  echo "usage: $0 lang1 lang2 task1 task2 corpus_dir"
  echo "usage: $0 task1 task2"
  echo ""
  echo "options:"
  echo "  --overwrite"
  echo "  --task_name={string}"
  echo "  --suffix{string}"
  echo "  --threads={integer}"
  echo "  --nbest={integer}"
  echo "  --method={string}"
  echo "  --lexmethod={lexmethod}"
}

#if [ ${#ARGS[@]} -lt 5 ]
if [ ${#ARGS[@]} -lt 2 ]
then
  usage
  exit 1
fi

task1=${ARGS[0]}
task2=${ARGS[1]}

taskname1=$(basename $task1)
taskname2=$(basename $task2)

mt_method1=$(get_mt_method $taskname1)
lang_task1_src=$(get_lang_src $taskname1)
lang_task1_trg=$(get_lang_trg $taskname1)
mt_method2=$(get_mt_method $taskname2)
lang_task2_src=$(get_lang_src $taskname2)
lang_task2_trg=$(get_lang_trg $taskname2)

if [ "${mt_method1}" == "${mt_method2}" ]; then
  mt_method=${mt_method1}
else
  echo "mt_method: ${mt_method1} != ${mt_method2}"
  exit 1
fi

if [ "${lang_task1_src}" == "${lang_task2_src}" ]; then
  lang_src=${lang_task1_src}
else
  echo "src: ${lang_task1_src} != ${lang_task2_src}"
  exit 1
fi

if [ "${lang_task1_trg}" == "${lang_task2_trg}" ]; then
  lang_trg=${lang_task1_trg}
else
  echo "trg: ${lang_task1_trg} != ${lang_task2_trg}"
  exit 1
fi

if [ $opt_task_name ]; then
  task=$opt_task_name
else
  task="integrate_${mt_method}_${lang_src}-${lang_trg}"
fi

if [ "$opt_suffix" ]; then
  task="${task}.${opt_suffix}"
fi

show_exec mkdir -p ${task}
LOG=${task}/log
echo "[${stamp} ${HOST}] $0 $*" >> ${LOG}

corpus="${task}/corpus"
langdir=${task}/LM_${lang_trg}
workdir="${task}/working"
transdir=${task}/TM
show_exec mkdir -p ${workdir}

if [ -f ${transdir}/model/moses.ini ]; then
  echo [autoskip] integrate
else
  show_exec mkdir -p ${transdir}/model
  ${dir}/wait-file.sh ${task1}/TM/model/moses.ini
  ${dir}/wait-file.sh ${task2}/TM/model/moses.ini

  # COPYING CORPUS
  show_exec mkdir -p ${corpus}
  show_exec cp ${task1}/corpus/devtest.true.{$lang_src,$lang_trg} ${corpus}
  show_exec cp ${task1}/corpus/test.true.{$lang_src,$lang_trg} ${corpus}
  show_exec cp ${task1}/corpus/dev.true.{$lang_src,$lang_trg} ${corpus}

  # COPYING LM
  show_exec mkdir -p ${langdir}
  show_exec cp ${task1}/LM_${lang_trg}/train.blm.${lang_trg} ${langdir}

  # FILTERING
  if [ "${mt_method}" == "pbmt" ]; then
    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task1}/TM/model/moses.ini ${corpus}/devtest.true.${lang_src}
    show_exec mv ${workdir}/filtered/phrase-table*.gz ${workdir}/phrase_filtered1.gz
    show_exec rm -rf ${workdir}/filtered
    show_exec ${MOSES}/scripts/training/filter-model-given-input.pl ${workdir}/filtered ${task2}/TM/model/moses.ini ${corpus}/devtest.true.${lang_src}
    show_exec mv ${workdir}/filtered/phrase-table*.gz ${workdir}/phrase_filtered2.gz
    show_exec rm -rf ${workdir}/filtered
  elif [ "${mt_method}" == "t2s" ]; then
    # REVERSING
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/ruletable/reverse.py ${task1}/TM/model/rule-table.gz ${workdir}/rule_s2t
#    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \| gzip \> ${workdir}/rule_filtered.gz
    show_exec cat ${workdir}/rule_s2t \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered.gz
  elif [ "${mt_method}" == "hiero" ]; then
    # FILTERING
#    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered.gz
    show_exec zcat ${task1}/TM/model/rule-table.gz \| ${TRAVATAR}/script/train/filter-rule-table.py ${corpus}/devtest.true.${lang_src} \> ${workdir}/rule_filtered
  fi

  if [ "${LEX_METHOD}" != "interpolate" ]; then
#    lexfile="${transdir}/model/lex_${lang_src}-${lang_trg}"
    lexfile="${transdir}/model/combined.lex"
    if [ -f "${lexfile}" ]; then
      echo [skip] calc lex probs
    else
      # 共起回数ピボットの場合、事前に語彙翻訳確率の算出が必要
      lexfile1="${task1}/TM/model/lex_${lang_src}-${lang_trg}"
      lexfile2="${task2}/TM/model/lex_${lang_src}-${lang_trg}"
      if [ -f "${lexfile1}" ]; then
        cp ${lexfile1} ${workdir}/lex1
      else
        show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task1}/corpus/train.clean.{$lang_src,$lang_trg} ${task1}/TM/model/aligned.grow-diag-final-and ${workdir}/lex1
      fi
      if [ -f "${lexfile2}" ]; then
        cp ${lexfile2} ${workdir}/lex2
      else
        if [ -f ${task2}/TM/model/align.lex ]; then
          show_exec cp ${task2}/TM/model/align.lex ${workdir}/lex2
        else
          show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/align2lex.py ${task2}/corpus/train.clean.{$lang_src,$lang_trg} ${task2}/TM/model/aligned.grow-diag-final-and ${workdir}/lex2
        fi
      fi
  #    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/pivot_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
      show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/combine_lex.py ${workdir}/lex1 ${workdir}/lex2 ${lexfile}
    fi
  fi
  # INTEGRATING
  options="--workdir ${workdir}"
  if [ "${THRESHOLD}" ]; then
    options="${options} --threshold ${THRESHOLD}"
  fi
  if [ "${opt_nbest}" ]; then
    options="${options} --nbest ${opt_nbest}"
  else
    options="${options} --nbest ${NBEST}"
  fi
  if [ -f "${lexfile}" ]; then
    options="${options} --lexfile ${lexfile}"
  fi
  if [ "${mt_method}" == "pbmt" ]; then
  #  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${lexfile} ${transdir}/model/phrase-table.gz ${options}
  #  show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${task1}/TM/model/phrase-table.gz ${task2}/TM/model/phrase-table.gz ${transdir}/model/phrase-table.gz ${options}
    show_exec PYTHONPATH=${PYTHONPATH} ${PYTHONPATH}/exp/phrasetable/integrate.py ${workdir}/phrase_filtered1.gz ${workdir}/phrase_filtered2.gz ${transdir}/model/phrase-table.gz ${options}
    show_exec sed -e "s/${task1}/${task}/g" ${task1}/TM/model/moses.ini \> ${transdir}/model/moses.ini
    show_exec rm -rf ${workdir}/phrase_filtered*.gz
    show_exec rm -rf ${workdir}/lex*
  fi
  show_exec rm -rf ${workdir}/integrate
fi

bindir=${task}/binmodel
# -- TUNING --
if [ ! $opt_overwrite ] && [ -f ${bindir}/moses.ini ]; then
  echo [autoskip] tuning
elif [ $opt_skip_tuning ]; then
  echo [skip] tuning
else
#if [ $opt_tuning ]; then
  show_exec ${dir}/tune-moses.sh ${corpus}/dev.true.${lang_src} ${corpus}/dev.true.${lang_trg} ${transdir}/model/moses.ini ${task} --threads=${THREADS}

  # -- BINARIZING --
  show_exec mkdir -p ${bindir}
  show_exec ${BIN}/processPhraseTable -ttable 0 0 ${transdir}/model/phrase-table.gz -nscores 5 -out ${bindir}/phrase-table
  show_exec sed -e "s/PhraseDictionaryMemory/PhraseDictionaryBinary/" -e "s#${transdir}/model/phrase-table\.gz#${bindir}/phrase-table#" -e "s#${transdir}/model/reordering-table\.wbe-msd-bidirectional-fe\.gz#${bindir}/reordering-table#" ${workdir}/mert-work/moses.ini \> ${bindir}/moses.ini

fi

# -- TESTING --
if [ ! $opt_overwrite ] && [ -f ${workdir}/score-dev.out ]; then
  echo [autoskip] testing
elif [ $opt_skip_test ]; then
  echo [skip] testing
else
#if [ $opt_test ]; then
  show_exec mkdir -p $workdir
  # -- TESTING PRAIN --
  show_exec rm -rf ${workdir}/filtered
  show_exec ${dir}/filter-moses.sh ${transdir}/model/moses.ini ${corpus}/test.true.${lang_src} ${workdir}/filtered
  show_exec ${dir}/test-moses.sh ${task} ${workdir}/filtered/moses.ini ${corpus}/test.true.${lang_src} ${corpus}/test.true.${lang_trg} plain --threads=${THREADS}
  show_exec rm -rf ${workdir}/filtered

  if [ -f ${bindir}/moses.ini ]; then
    # -- TESTING BINARISED --
    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/test.true.${lang_src} ${corpus}/test.true.${lang_trg} tuned --threads=${THREADS}
    show_exec ${dir}/test-moses.sh ${task} ${bindir}/moses.ini ${corpus}/dev.true.${lang_src} ${corpus}/dev.true.${lang_trg} dev --threads=${THREADS}
  fi
fi

head ${workdir}/score*

echo "##### End of script: $0 $*"

