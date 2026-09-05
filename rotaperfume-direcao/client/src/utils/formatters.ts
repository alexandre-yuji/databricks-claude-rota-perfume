// O warehouse devolve número como STRING no JSON, mesmo quando o tipo gerado
// diz `number` — por isso todo valor passa por Number() antes de formatar ou
// somar. Sem isso, R$ vira "582799.4988012867" e "7" + "12" vira "712".

export const toNumber = (value: number | string): number => Number(value);

export const formatBRL = (value: number | string): string =>
  Number(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });

export const formatInt = (value: number | string): string => Number(value).toLocaleString('pt-BR');

export const formatScorePercent = (value: number | string): string => `${Math.round(Number(value) * 100)}%`;

export const formatPercent1 = (value: number | string): string => `${Number(value).toFixed(1)}%`;

export const formatDateBR = (value: string): string => {
  const [ano, mes, dia] = value.split('-');
  return `${dia}/${mes}/${ano}`;
};
