"""Print-sized thesis figures from archived counts and scored records.

No model is fitted. PDF text remains vector-based. Split heatmaps retain the
same matrices, response-change axes, row normalization and shared colour scale.
Run after generate_publication_figures.py when rebuilding the manuscript.
"""
from pathlib import Path
import json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.ticker import PercentFormatter
import numpy as np
import pandas as pd
import generate_publication_figures as pub

ROOT=pub.RESULT
PICS=pub.PAPER_PICS
OUT=pub.EVAL/'publication/audits/thesis_figures'
CHECKS=[]

def save(fig,name):
    p=PICS/name;p.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(p,dpi=300,facecolor='white')
    plt.close(fig)

def information_ladder():
    tables=pub.EVAL/'manuscript/tables'
    no=pd.read_csv(tables/'rq1_ordinal_covariates_only_comparison.csv')
    prior=pd.read_csv(tables/'rq2_ordinal_prior_state_comparison.csv')
    archived=pd.read_csv(pub.EVAL/'figures/information_ladder_selection_details.csv').set_index('Task')
    fig,axes=plt.subplots(1,4,figsize=(6.3,4.8),sharex=True,sharey=True)
    labels=['Baseline\nCovariates-only ordinal probit','LLM\nNo-time',
            'Baseline\nPrior-wave modal','Baseline\nCarry-forward',
            'Baseline\nLag + covariates ordinal probit','LLM\nTrajectory']
    baseline_color,llm_color='#64788B','#9C427E'
    cols=[baseline_color,llm_color,baseline_color,baseline_color,baseline_color,llm_color]
    rows=np.array([0.2,1.2,3.3,4.3,5.3,6.3])
    for ax,task in zip(axes,pub.TASK_DIRS):
        a=no.loc[no.Task.eq(task)].sort_values('accuracy_prompt',ascending=False).iloc[0]
        b=prior.loc[prior.Task.eq(task)].sort_values('accuracy_trajectory',ascending=False).iloc[0]
        vals=[a.accuracy_ordinal,a.accuracy_prompt,b.accuracy_majority,b.accuracy_cf,b.accuracy_ordinal,b.accuracy_trajectory]
        oracle=archived.loc[task,['covariates_only','best_nontrajectory','modal','carry_forward','lag_covariates','best_trajectory']].to_numpy(dtype=float)
        assert np.allclose(vals,oracle,atol=1e-12)
        for y in rows:ax.axhline(y,color='#E8EDF1',lw=.6,zorder=0)
        ax.scatter(vals,rows,s=28,c=cols,edgecolor='white',linewidth=.45,zorder=3)
        for value,y in zip(vals,rows):
            dx,ha=(-.06,'right') if value>.65 else (.06,'left')
            ax.text(value+dx,y,f'{value:.1%}',fontsize=7.1,ha=ha,va='center',color='#263746')
        ax.axhline(2.05,color='#9CACB7',ls=(0,(3,3)),lw=.7)
        ax.set_xlim(-.03,1.03);ax.set_ylim(6.95,-1.05)
        ax.set_xticks([0,.5,1],['0','50','100'])
        ax.set_yticks(rows);ax.tick_params(axis='y',left=False,labelleft=False)
        ax.tick_params(axis='x',labelsize=8,length=3,color='#ADB8C1')
        ax.spines['left'].set_visible(False)
        ax.grid(axis='x',color='#E2E8ED',lw=.6);ax.set_axisbelow(True)
        ax.set_title('Grouped' if 'grouped' in task else 'Original scale',fontsize=8.4,pad=9)
        CHECKS.append(dict(figure='information_ladder',task=task,values=vals,unchanged=True))
    fig.subplots_adjust(left=.345,right=.975,bottom=.13,top=.84,wspace=.30)
    from matplotlib.transforms import blended_transform_factory
    label_transform=blended_transform_factory(fig.transFigure,axes[0].transData)
    for label,y,color in zip(labels,rows,cols):
        axes[0].text(.012,y,label,transform=label_transform,clip_on=False,
                     va='center',fontsize=8.5,color=color,
                     fontweight='bold' if label.startswith('LLM\n') else 'normal')
    for y,label in [(-.72,'Profile information only'),(2.55,'Preceding-wave information')]:
        axes[0].text(.012,y,label,transform=label_transform,clip_on=False,
                     va='center',fontsize=8,color='#183653',fontweight='bold')
    for start,title in [(0,'Climate-growth'),(2,'Left-right')]:
        x=(axes[start].get_position().x0+axes[start+1].get_position().x1)/2
        fig.text(x,.935,title,ha='center',va='center',fontsize=10,fontweight='bold',color='#183653')
    fig.text(.66,.045,'Exact-match accuracy (%)',ha='center',fontsize=9)
    save(fig,'Figure_1_information_ladder_print.pdf')

def stable_changing():
    data=pub.model_scale_data()
    archived=pd.read_csv(pub.EVAL/'tables/stable_changing_split_table.csv')
    fig,axes=plt.subplots(3,1,figsize=(6.3,5.9),sharex=True,sharey=True)
    panels=[('stable_accuracy','Acc. stable','A. Accuracy among stable transitions'),('changed_accuracy','Acc. changed','B. Accuracy among changing transitions'),('false_persistence','False persistence among changers','C. False persistence among parsed changing transitions')]
    handles=[]
    for ax,(metric,old_col,title) in zip(axes,panels):
        for j,model in enumerate(pub.MODEL_ORDER):
            key=model.replace(' (4-bit)','');sub=data.loc[data.Model.eq(key)].set_index('task')
            vals=[sub.loc[t,metric] for t in pub.TASK_DIRS]
            old=archived.loc[archived.Model.map(pub.short_model).eq(model)].set_index('Task')
            assert np.allclose(vals,[old.loc[t,old_col] for t in pub.TASK_DIRS],atol=.000501)
            ax.scatter(np.arange(4)+(j-2)*.09,vals,s=27,color=pub.MODEL_COLORS[model],edgecolor='white',linewidth=.4,zorder=3)
            CHECKS.append(dict(figure='stable_changing',model=model,metric=metric,values=vals,agrees_with_reported_rounding=True))
        pub.percent_axis(ax)
        ax.set_ylim(-.04,1.04)
        ax.set_yticks([0,.5,1]);ax.tick_params(labelsize=9)
        ax.set_title(title,fontsize=9.5,fontweight='bold',loc='left',pad=5)
    axes[-1].set_xticks(range(4),[pub.task_label(t).replace(', ','\n') for t in pub.TASK_DIRS],fontsize=8.5)
    handles=[Line2D([],[],marker='o',ls='',color=pub.MODEL_COLORS[m],label=m,markersize=5) for m in pub.MODEL_ORDER]
    fig.legend(handles=handles,loc='lower center',ncol=3,fontsize=8,frameon=False,columnspacing=1)
    fig.subplots_adjust(left=.09,right=.99,top=.96,bottom=.21,hspace=.5)
    save(fig,'Figure_3_stable_changing_split_print.pdf')

def main_anchor():
    source=pub.parse_heatmap_files(pub.EVAL/'analysis_1500/trajectory_heatmap/anchored_change')
    fig,axes=plt.subplots(2,3,figsize=(6.3,4.65),sharex=True,sharey=True)
    values=list(range(-2,3))
    for ax,model in zip(axes.flat,pub.MODEL_ORDER):
        df=pd.concat([d for (_,m),d in source.items() if m==model]).groupby(['delta_H','delta_L'],as_index=False)['count'].sum()
        df['row_percent']=df['count']/df.groupby('delta_H')['count'].transform('sum')
        matrix=pub.heat_matrix(df,values,values)
        im=ax.imshow(matrix,origin='lower',cmap=pub.GREEN_CMAP,vmin=0,vmax=1,interpolation='nearest',aspect='equal')
        assert np.array_equal(im.get_array(),matrix)
        ax.set_title(model,fontsize=9,fontweight='bold',pad=7)
        ax.set_xticks(range(5),values,fontsize=8);ax.set_yticks(range(5),values,fontsize=8)
        ax.tick_params(labelbottom=True,labelleft=True,length=2)
        ax.axvline(2,color='#00796B',ls='--',lw=.8)
        for iy,ix in np.argwhere(matrix>=.05):
            ax.text(ix,iy,f'{matrix[iy,ix]:.0%}',ha='center',va='center',fontsize=8)
        CHECKS.append(dict(figure='main_anchor',model=model,counts=int(df['count'].sum()),matrix_unchanged=True))
    axes[1,2].set_visible(False)
    fig.subplots_adjust(left=.10,right=.99,top=.91,bottom=.13,wspace=.24,hspace=.39)
    cax=fig.add_axes([.76,.20,.025,.25]);cb=fig.colorbar(im,cax=cax)
    cb.ax.yaxis.set_major_formatter(PercentFormatter(1));cb.ax.tick_params(labelsize=8)
    cb.set_label('Row percentage',fontsize=9)
    fig.supylabel('Observed response change',x=.015,fontsize=9)
    fig.supxlabel('Predicted change from the observed preceding answer',y=.025,fontsize=9)
    save(fig,'Figure_4_persistence_heatmap_left_right_grouped_print.pdf')

def appendix_heatmaps():
    manifest=[]
    for mode,first in [('anchored_change',5),('self_trajectory',9)]:
        for i,(task,directory) in enumerate(pub.TASK_DIRS.items()):
            files=pub.parse_heatmap_files(pub.EVAL/directory/'trajectory_heatmap'/mode)
            waves=sorted({w for w,_ in files})
            values=sorted(set().union(*(set(d.delta_H.astype(int))|set(d.delta_L.astype(int)) for d in files.values())))
            per_page=4 if i%2==0 else 3
            name=('climate_growth' if i<2 else 'left_right')+('_grouped' if i%2==0 else '_original')
            suffix='anchored_change_heatmap' if mode=='anchored_change' else 'self_trajectory_heatmap'
            stem=f'D{first+i:02d}_{name}_{suffix}'
            groups=np.array_split(waves,int(np.ceil(len(waves)/per_page)))
            for page,group in enumerate(groups,1):
                selected=[int(w) for w in group];n=len(selected)
                row_height=1.1 if i%2==0 else 1.3
                fig,axes=plt.subplots(n,5,figsize=(9.13,row_height*n+0.55),sharex=True,sharey=True,squeeze=False)
                for r,wave in enumerate(selected):
                    for c,model in enumerate(pub.MODEL_ORDER):
                        ax=axes[r,c];matrix=pub.heat_matrix(files[(wave,model)],values,values)
                        im=ax.imshow(matrix,origin='lower',cmap=pub.GREEN_CMAP,vmin=0,vmax=1,interpolation='nearest',aspect='auto')
                        assert np.array_equal(im.get_array(),matrix)
                        ticks=[k for k,v in enumerate(values) if (len(values)<=7 or v%5==0)]
                        ax.set_xticks(ticks,[values[k] for k in ticks]);ax.set_yticks(ticks,[values[k] for k in ticks])
                        ax.tick_params(labelsize=8,labelbottom=True,length=2,pad=2)
                        if r==0:ax.set_title(model,fontsize=9,fontweight='bold',pad=7)
                        if c==0:ax.set_ylabel(f'Wave {wave}\nObserved change',fontsize=8)
                        ax.axvline(values.index(0),color='#00796B',ls='--',lw=.6)
                        CHECKS.append(dict(figure=stem,wave=wave,model=model,matrix_unchanged=True,shape=list(matrix.shape),range=[0,1]))
                fig.subplots_adjust(left=.07,right=.865,top=1-.23/fig.get_figheight(),bottom=.38/fig.get_figheight(),wspace=.14,hspace=.35)
                bar=fig.add_axes([.887,.3,.012,.4]);cb=fig.colorbar(im,cax=bar)
                cb.ax.yaxis.set_major_formatter(PercentFormatter(1));cb.ax.tick_params(labelsize=8,pad=2)
                cb.set_label('Row percentage',fontsize=8,labelpad=5)
                fig.supxlabel('Predicted change from the observed preceding answer' if mode=='anchored_change' else 'Change between consecutive one-step predictions',fontsize=9,y=.02)
                filename=f'appendix/{stem}_part{page}.pdf';save(fig,filename)
                manifest.append(dict(stem=stem,page=page,waves=selected,file=filename))
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'heatmap_manifest.json').write_text(json.dumps(manifest,indent=2))

def main():
    pub.setup_style()
    information_ladder();stable_changing();main_anchor();appendix_heatmaps()
    (OUT/'figure_checks.json').write_text(json.dumps(CHECKS,indent=2))
    print(f'Generated print PDFs; verified {len(CHECKS)} plotted comparisons and matrices.',flush=True)

if __name__=='__main__':main()
