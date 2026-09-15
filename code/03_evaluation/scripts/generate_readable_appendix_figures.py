"""Generate selected appendix figures at their final printed dimensions.

Use --output-dir and --audit-dir to override local publication destinations.
Only archived evaluation records are read; no statistical model is refitted.
"""
from pathlib import Path
import argparse,hashlib,json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import PercentFormatter
import numpy as np
import pandas as pd
import generate_publication_figures as pub


def capture(fig):
    return [dict(bars=[[float(p.get_x()),float(p.get_y()),float(p.get_width()),float(p.get_height())]
                      for p in ax.patches],
                 points=[np.asarray(c.get_offsets(),dtype=float).tolist() for c in ax.collections],
                 colors=[c.get_facecolors().tolist() for c in ax.collections],
                 lines=[np.asarray(l.get_ydata(),dtype=float).tolist() for l in ax.lines])
            for ax in fig.axes]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--output-dir',type=Path,default=pub.PAPER_PICS)
    parser.add_argument('--audit-dir',type=Path,default=pub.EVAL/'publication/audits/appendix_figures')
    args=parser.parse_args()
    pics=args.output_dir.resolve()
    out=args.audit_dir.resolve();out.mkdir(parents=True,exist_ok=True)
    baseline={};after={};files={};bounds=[]
    pub.setup_style()
    data=pub.model_scale_data()
    pub.model_scale_data=lambda:data.copy()
    pub.CURATED=out/'baseline_curated'

    def save_baseline(fig,paper_name,curated_name):
        baseline[paper_name]=capture(fig)
        path=out/'baseline_figures'/paper_name;path.parent.mkdir(parents=True,exist_ok=True)
        fig.savefig(path,dpi=180,bbox_inches='tight',facecolor='white')
        plt.close(fig)
    pub.save_figure=save_baseline
    pub.figure_trajectory_contrast()
    pub.appendix_current_state_baselines()
    pub.figure_model_scale()

    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':9,'pdf.fonttype':42,
                         'axes.labelsize':9,'xtick.labelsize':8.5,'ytick.labelsize':8.5})
    def save(fig,name,old_name):
        fig.canvas.draw();renderer=fig.canvas.get_renderer()
        for artist in fig.findobj(matplotlib.text.Text):
            if artist.get_visible() and artist.get_text():
                box=artist.get_window_extent(renderer)
                if not (box.x0>=-1 and box.y0>=-1 and box.x1<=fig.bbox.width+1 and box.y1<=fig.bbox.height+1):
                    bounds.append(dict(file=name,text=artist.get_text(),bounds=list(box.extents)))
        after[old_name]=capture(fig)
        target=pics/name;target.parent.mkdir(parents=True,exist_ok=True)
        fig.savefig(target,facecolor='white')
        fig.savefig(out/(Path(name).stem+'.png'),dpi=180,facecolor='white')
        files[old_name]=name
        plt.close(fig)

    # A.1: percentage-point differences use numerical ticks.
    run=pub.latest_common_run()
    df=pd.read_csv(run/'trajectory_vs_best_nontrajectory_common_sample.csv')
    df['task_publication']=[pub.task_label(v,r) for v,r in zip(df['variant'],df['representation'])]
    df['model_publication']=df['model'].map(pub.short_model)
    indexed=df.set_index(['task_publication','model_publication'])
    fig,ax=plt.subplots(figsize=(6.3,3.7))
    x=np.arange(4);width=.15
    for j,model in enumerate(pub.MODEL_ORDER):
        vals=np.array([indexed.loc[(task,model),'trajectory_minus_best_non'] for task in pub.TASK_ORDER])
        ax.bar(x+(j-2)*width,100*vals,width=width,color=pub.MODEL_COLORS[model],label=model)
    ax.axhline(0,color='#666666',lw=.8,ls='--')
    ax.set_ylim(0,60);ax.set_yticks(range(0,61,10))
    ax.set_xticks(x,[t.replace(', ','\n') for t in pub.TASK_ORDER],fontsize=8.5)
    ax.set_ylabel('Accuracy gain\n(percentage points)',fontsize=9.5)
    ax.grid(axis='y');ax.set_axisbelow(True)
    fig.suptitle('Accuracy gain from trajectory prompting',fontsize=11,fontweight='bold',y=.96)
    handles,labels=ax.get_legend_handles_labels()
    fig.legend(handles,labels,loc='lower center',bbox_to_anchor=(.52,.005),ncol=3,frameon=False,fontsize=8.3,columnspacing=1.0)
    fig.subplots_adjust(left=.14,right=.99,bottom=.25,top=.85)
    save(fig,'Figure_A1_trajectory_gain_print.pdf','Figure_2_trajectory_advantage_vs_best_nontrajectory.png')

    # A.3-A.4: each of the paired figures is drawn at the actual 160 mm width.
    cov,stat=pub.baseline_frames()
    stem_names=['B1_climate_growth_grouped','B2_climate_growth_original','B3_left_right_grouped','B4_left_right_original']
    metrics=[('Prior-wave modal','PreviousWaveModal','Modal, designated preceding wave'),
             ('Covariates-only probit','CovariatesOnly','Covariates-only ordinal probit'),
             ('Trajectory LLM','Trajectory','Trajectory accuracy'),
             ('LLM prompt','LLMPrompt','Information-condition accuracy')]
    for task,stem in zip(pub.TASK_ORDER,stem_names):
        fig,axes=plt.subplots(1,3,figsize=(6.3,3.45),sharex=True,sharey=True)
        task_cov=cov[cov.task_publication.eq(task)]
        task_stat=stat[stat.task_publication.eq(task)].set_index('model_publication')
        for ax,prompt in zip(axes,pub.PROMPT_ORDER[:3]):
            sub=task_cov[task_cov.prompt_publication.eq(prompt)].set_index('model_publication')
            y=np.arange(5);height=.18
            for j,(label,column,color_key) in enumerate(metrics):
                vals=task_stat.loc[pub.MODEL_ORDER,column].to_numpy() if column=='Trajectory' else sub.loc[pub.MODEL_ORDER,column].to_numpy()
                ax.barh(y+(j-1.5)*height,vals,height=height,color=pub.METRIC_COLORS[color_key],label=label)
            ax.set_title(prompt,fontsize=9.2,fontweight='bold',pad=7)
            ax.set_xlim(0,1);ax.set_xticks([0,.5,1])
            ax.xaxis.set_major_formatter(PercentFormatter(1,decimals=0))
            ax.set_yticks(y,[m.replace(' (4-bit)','\n(4-bit)') for m in pub.MODEL_ORDER],fontsize=8.7)
            ax.invert_yaxis();ax.grid(axis='x');ax.set_axisbelow(True)
            ax.tick_params(axis='both',length=2,pad=3)
        fig.suptitle(f'Current-state comparisons for {task}',fontsize=10.2,y=.98)
        handles,labels=axes[0].get_legend_handles_labels()
        fig.legend(handles,labels,loc='lower center',bbox_to_anchor=(.5,-.005),ncol=2,frameon=False,fontsize=8.5)
        fig.text(.60,.17,'Exact-match current-state accuracy',fontsize=9,ha='center')
        fig.subplots_adjust(left=.24,right=.965,bottom=.28,top=.80,wspace=.22)
        old=f'appendix/{stem}_all_prompts_vs_covariates_only.png'
        save(fig,f'appendix/{stem}_all_prompts_vs_covariates_only_print.pdf',old)

    # A.7: maintain all 16 panels and the original model-family palette.
    df=data.copy();df['task_publication']=df.task.map(pub.task_label)
    metrics=[('nontrajectory_accuracy','A. No-time\naccuracy (%)',(-.025,.72),[0,.3,.6]),
             ('trajectory_minus_carry_forward','B. Trajectory minus\ncarry-forward\n(percentage points)',(-26,3),[-20,-10,0]),
             ('changed_accuracy','C. Changing-transition\naccuracy (%)',(-.006,.18),[0,.05,.10,.15]),
             ('false_persistence','D. False persistence\n(parsed changers, %)',(-.035,1.035),[0,.5,1])]
    fig,axes=plt.subplots(4,4,figsize=(9.13,5.0),sharex='col')
    colors={'Mistral':'#4C78A8','Qwen':'#54A24B','Llama':'#E45756'}
    tick_labels=['7B','7B\n4-bit','32B','70B','72B']
    for col,task in enumerate(pub.TASK_ORDER):
        sub=df[df.task_publication.eq(task)].sort_values('model_order')
        for row,(metric,label,ylim,ticks) in enumerate(metrics):
            ax=axes[row,col];scale=100 if row==1 else 1
            ax.scatter(np.arange(5),scale*sub[metric],s=24,c=[colors[f] for f in sub.family],edgecolor='white',linewidth=.4,zorder=3)
            ax.set_ylim(*ylim);ax.set_yticks(ticks);ax.set_xlim(-.4,4.4)
            if row!=1:ax.yaxis.set_major_formatter(PercentFormatter(1,decimals=0))
            ax.tick_params(axis='y',labelsize=8,length=2,pad=2)
            ax.grid(axis='y');ax.set_axisbelow(True)
            if row==0:
                ax.set_title(task.replace(', ','\n'),fontsize=9.2,fontweight='bold',pad=6)
                ax.axhline(float(sub.covariates_only_accuracy.iloc[0]),color='#444444',ls='--',lw=.8)
            if row==1:ax.axhline(0,color='#444444',ls='--',lw=.8)
            if row==3:
                ax.set_xticks(range(5),tick_labels,fontsize=8.5)
                ax.tick_params(axis='x',length=2,pad=4)
            else:ax.tick_params(axis='x',bottom=False,labelbottom=False)
    fig.subplots_adjust(left=.215,right=.99,bottom=.20,top=.84,hspace=.48,wspace=.29)
    for row,(_,label,_,_) in enumerate(metrics):
        pos=axes[row,0].get_position()
        fig.text(.014,(pos.y0+pos.y1)/2,label,fontsize=8.7,ha='left',va='center',linespacing=1.2)
    fig.suptitle('Descriptive patterns across model configurations',fontsize=11.2,fontweight='bold',y=.985)
    fig.text(.59,.112,'Nominal parameter count',fontsize=8.5,ha='center')
    family_labels={'Mistral':'Mistral','Qwen':'Qwen (2.5)','Llama':'Llama (3.3)'}
    handles=[Line2D([],[],marker='o',ls='',color=c,label=family_labels[f],markersize=5) for f,c in colors.items()]
    fig.legend(handles=handles,title='Model family',loc='lower center',bbox_to_anchor=(.57,.002),ncol=3,frameon=False,fontsize=8.5,title_fontsize=8.5)
    save(fig,'Figure_A7_model_scale_print.pdf','Figure_5_model_scale_robustness.png')

    # Match every plotted number to the current renderer, allowing only the pp conversion.
    total=0
    for name,old_axes in baseline.items():
        new_axes=after[name];assert len(old_axes)==len(new_axes)
        for i,(old,new) in enumerate(zip(old_axes,new_axes)):
            bars=np.array(new['bars'])
            if len(bars):
                if name.startswith('Figure_2_'):bars[:,3]/=100
                assert np.allclose(bars,old['bars'],rtol=0,atol=1e-12),(name,i,'bars')
                total+=len(bars)
            points=np.array(new['points'])
            if points.size:
                if name.startswith('Figure_5_') and i//4==1:points[:,:,1]/=100
                assert np.allclose(points,old['points'],rtol=0,atol=1e-12),(name,i,'points')
                assert new['colors']==old['colors'],(name,i,'family colors')
                total+=points.shape[0]*points.shape[1]
            assert np.allclose(new['lines'],old['lines'],rtol=0,atol=1e-12),(name,i,'reference lines')
    assert total==340,total
    assert not bounds,bounds
    report=dict(plotted_values_verified=total,all_values_preserved=True,only_difference_conversion='Accuracy differences multiplied by 100 for percentage-point axes',
                family_colors_preserved=True,text_within_figure_bounds=True,files=files,
                baseline_image_matches={name:hashlib.sha256((pics/name).read_bytes()).hexdigest()==hashlib.sha256((out/'baseline_figures'/name).read_bytes()).hexdigest() for name in baseline})
    (out/'figure_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(report),flush=True)


if __name__=='__main__':main()
